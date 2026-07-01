"""
Minimal REST API for the HMS daemon.
Exposes endpoints under /api and keeps legacy endpoints for compatibility.
Integrates the APScheduler scheduler into the FastAPI lifespan.
"""

import asyncio
import gc
import json
import logging
import time
from contextlib import asynccontextmanager
import os

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from hms.daemon.scheduler import (
    check_scheduler_running,
    get_jobs_status,
    start_scheduler,
    stop_scheduler,
)
from hms.lib.docker import docker_manager
from hms.lib.notify import send as notify
from hms.lib.stacks import stack_metadata
from hms.lib.config import config_manager

logger = logging.getLogger(__name__)

# Global variables for tracking
_start_time = time.time()
_cache = {"dashboard": {"ts": 0.0, "data": None}, "metrics": {"ts": 0.0, "data": None}}
_CACHE_TTL_SECONDS = int(os.environ.get("HMS_DASHBOARD_TTL", "10"))
_STACK_PREFIX = "hms-"
_prev_net_totals: dict = {}  # {container_name: {"rx": int, "tx": int}}


async def _wait_for_stacks_ready(timeout_s: int = 300, poll_s: int = 3) -> list[str]:
    """
    Poll until all enabled stacks are ready (running + healthy).
    Returns stacks that are not ready when the deadline is reached or all stacks
    have settled (ready or unhealthy — no point waiting further for unhealthy ones).
    """
    enabled = [s for s in stack_metadata.list_stacks() if config_manager.is_stack_enabled(s)]
    if not enabled:
        return []
    deadline = time.monotonic() + timeout_s
    loop = asyncio.get_running_loop()
    while True:
        pending = []
        not_ready = []
        for name in enabled:
            state = await loop.run_in_executor(None, docker_manager.get_stack_readiness, name)
            if state == "ready":
                pass
            elif state == "unhealthy":
                not_ready.append(name)
            else:  # "empty" or "starting"
                pending.append(name)
        if not pending or time.monotonic() >= deadline:
            return not_ready + pending
        await asyncio.sleep(poll_s)


def _build_startup_message(not_ready: list[str]) -> str:
    lines = []

    domain = config_manager.get_config_value("global.domain", "")
    if domain:
        lines.append(f"🌐 {domain}")

    enabled = [s for s in stack_metadata.list_stacks() if config_manager.is_stack_enabled(s)]
    if enabled:
        lines.append(f"📦 Stacks ({len(enabled)}): {' · '.join(enabled)}")

    if not_ready:
        lines.append(f"⚠️ Not ready after 10min: {' · '.join(not_ready)}")

    sysinfo = _get_system_info()
    parts = []
    disk = sysinfo.get("disk", {}).get("usage_percent")
    mem = sysinfo.get("memory", {}).get("usage_percent")
    load_status = sysinfo.get("load", {}).get("status")
    if disk is not None and disk != "unknown":
        parts.append(f"disk {disk}%")
    if mem is not None and mem != "unknown":
        parts.append(f"mem {mem}%")
    if load_status and load_status != "unknown":
        parts.append(f"load {load_status}")
    if parts:
        lines.append(f"💻 {' · '.join(parts)}")

    return "\n".join(lines)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan management.
    Starts the scheduler on startup and stops it on shutdown.
    """
    # Startup
    logger.info("⏱️  Starting scheduler...")
    start_scheduler()
    gc.freeze()  # exclude startup objects from future GC passes

    # Show configured jobs
    jobs = get_jobs_status()
    logger.info(f"📋 Scheduler started with {len(jobs)} job(s)")
    for job in jobs:
        logger.info(f"   ✓ {job['name']} ({job['id']}) - {job['trigger']}")

    async def _notify_when_ready():
        not_ready = await _wait_for_stacks_ready(timeout_s=600, poll_s=3)
        notify("🚀 HMS started", _build_startup_message(not_ready))

    asyncio.create_task(_notify_when_ready())

    yield

    # Shutdown
    logger.info("🛑 Stopping scheduler...")
    uptime = _format_uptime(int(time.time() - _start_time))
    notify("🛑 HMS stopped", f"⏱️ Uptime: {uptime}")
    stop_scheduler()
    logger.info("✅ Scheduler stopped")


# Create FastAPI app with lifespan
app = FastAPI(
    title="HMS Daemon API",
    description="Internal HMS daemon API for healthcheck",
    version="0.1.0",
    docs_url=None,  # Disable docs in production
    redoc_url=None,
    lifespan=lifespan,
)


@app.get("/health")
async def health() -> JSONResponse:
    """
    Healthcheck endpoint.
    Verifies the scheduler is running and returns basic status.
    """
    try:
        scheduler_running = check_scheduler_running()
        uptime = int(time.time() - _start_time)

        if not scheduler_running:
            return JSONResponse(
                status_code=503,
                content={
                    "status": "unhealthy",
                    "scheduler_running": False,
                    "uptime_seconds": uptime,
                    "message": "Scheduler is not running",
                },
            )

        # Count active jobs
        jobs = get_jobs_status()
        jobs_count = len([j for j in jobs if not j["id"].startswith("__internal_")])

        return JSONResponse(
            content={
                "status": "healthy",
                "scheduler_running": True,
                "uptime_seconds": uptime,
                "jobs_count": jobs_count,
            }
        )

    except Exception as e:
        logger.error(f"❌ Error in healthcheck: {e}", exc_info=True)
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": str(e),
            },
        )


@app.get("/api/health")
async def api_health() -> JSONResponse:
    """Health endpoint (API namespace)."""
    return await health()


def _format_uptime(seconds: int) -> str:
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours or days:
        parts.append(f"{hours}h")
    parts.append(f"{minutes}m")
    return " ".join(parts)


def _get_system_info() -> dict:
    uptime_seconds = int(time.time() - _start_time)
    info = {
        "server_name": "Home Server",
        "uptime_seconds": uptime_seconds,
        "uptime": _format_uptime(uptime_seconds),
        "load": {"value": "unknown", "status": "unknown"},
        "memory": {"usage_percent": "unknown", "status": "unknown"},
        "disk": {"usage_percent": "unknown", "status": "unknown"},
    }

    try:
        with open("/proc/loadavg", "r", encoding="utf-8") as handle:
            load = float(handle.read().strip().split(" ")[0])
            info["load"] = {
                "value": f"{load:.2f}",
                "status": "high" if load > 2.0 else "medium" if load > 1.0 else "low",
            }
    except Exception:
        pass

    try:
        mem_total = None
        mem_available = None
        with open("/proc/meminfo", "r", encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("MemTotal:"):
                    mem_total = int(line.split()[1])
                elif line.startswith("MemAvailable:"):
                    mem_available = int(line.split()[1])
        if mem_total and mem_available is not None:
            usage_percent = int(((mem_total - mem_available) / mem_total) * 100)
            info["memory"] = {
                "usage_percent": usage_percent,
                "status": (
                    "high" if usage_percent > 80 else "medium" if usage_percent > 60 else "low"
                ),
            }
    except Exception:
        pass

    try:
        import shutil

        disk = shutil.disk_usage("/")
        usage_percent = int((disk.used / disk.total) * 100)
        info["disk"] = {
            "usage_percent": usage_percent,
            "status": "high" if usage_percent > 85 else "medium" if usage_percent > 70 else "low",
        }
    except Exception:
        pass

    return info


def _build_dashboard_data() -> dict:
    system = _get_system_info()
    stacks_data = []
    domain = config_manager.get_config_value("global.domain", "")

    total_running = 0
    total_stopped = 0
    total_containers = 0

    for stack_name in stack_metadata.list_stacks():
        if not config_manager.is_stack_enabled(stack_name):
            continue
        services = []
        service_counts = docker_manager.get_stack_service_counts(stack_name)
        stack_counts = docker_manager.get_stack_container_counts(stack_name)

        total_running += stack_counts.get("running", 0)
        total_stopped += stack_counts.get("stopped", 0)
        total_containers += stack_counts.get("total", 0)

        for service in stack_metadata.list_services(stack_name):
            hosts = stack_metadata.get_service_hosts(stack_name, service)
            endpoints = []
            for host in hosts:
                if "${DOMAIN}" in host and domain:
                    host = host.replace("${DOMAIN}", domain)
                endpoints.append({"host": host, "url": f"https://{host}"})
            counts = service_counts.get(service, {})
            has_endpoint = len(endpoints) > 0
            services.append(
                {
                    "name": service,
                    "description": stack_metadata.get_service_description(stack_name, service)
                    or "",
                    "public": (
                        stack_metadata.is_service_public(stack_name, service)
                        if has_endpoint
                        else False
                    ),
                    "endpoints": endpoints,
                    "state": counts.get("state", "stopped"),
                    "has_endpoint": has_endpoint,
                }
            )

        stacks_data.append(
            {
                "name": stack_name,
                "description": stack_metadata.get_description(stack_name) or "",
                "status": docker_manager.get_stack_status(stack_name),
                "containers": stack_counts,
                "services": services,
            }
        )

    available = [
        {"name": s, "description": stack_metadata.get_description(s) or ""}
        for s in stack_metadata.list_stacks()
        if not config_manager.is_stack_enabled(s)
    ]

    system["totals"] = {
        "stacks": len(stacks_data),
        "containers": {
            "running": total_running,
            "stopped": total_stopped,
            "total": total_containers,
        },
    }

    return {
        "system": system,
        "stacks": stacks_data,
        "available": available,
        "generated_at": time.time(),
    }


@app.get("/api/dashboard")
async def dashboard() -> JSONResponse:
    cached = _cache["dashboard"]
    now = time.time()
    if cached["data"] and (now - cached["ts"]) < _CACHE_TTL_SECONDS:
        return JSONResponse(content=cached["data"])

    data = _build_dashboard_data()
    _cache["dashboard"] = {"ts": now, "data": data}
    return JSONResponse(content=data)


def _parse_mem_mb(s: str) -> float:
    """Parse docker stats memory string like '123MiB', '1.2GiB', '456kB'."""
    for suffix, factor in [
        ("GiB", 1024.0),
        ("MiB", 1.0),
        ("KiB", 1 / 1024.0),
        ("GB", 1024.0),
        ("MB", 1.0),
        ("kB", 1 / 1024.0),
        ("B", 1 / 1048576.0),
    ]:
        if s.endswith(suffix):
            try:
                return round(float(s[: -len(suffix)]) * factor, 1)
            except ValueError:
                return 0.0
    return 0.0


def _parse_bytes(s: str) -> int:
    """Parse docker stats bytes string like '1.23kB', '4.56MB', '789B'."""
    for suffix, factor in [("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("B", 1.0)]:
        if s.endswith(suffix):
            try:
                return int(float(s[: -len(suffix)]) * factor)
            except ValueError:
                return 0
    return 0


async def _fetch_docker_stats() -> dict:
    """Fetch per-stack CPU/RAM/network metrics from docker stats."""
    global _prev_net_totals

    proc = await asyncio.create_subprocess_exec(
        "docker",
        "stats",
        "--no-stream",
        "--no-trunc",
        "--format",
        "{{json .}}",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()

    result: dict = {}
    new_net_totals: dict = {}

    for line in stdout.decode().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            s = json.loads(line)
        except json.JSONDecodeError:
            continue

        name = s.get("Name", "")
        if not name.startswith(_STACK_PREFIX):
            continue

        rest = name[len(_STACK_PREFIX) :]
        stack_name = rest.split("-")[0] if "-" in rest else rest

        cpu_str = s.get("CPUPerc", "0%").rstrip("%")
        try:
            cpu = float(cpu_str)
        except ValueError:
            cpu = 0.0

        mem_mb = _parse_mem_mb(s.get("MemUsage", "0MiB / 0MiB").split("/")[0].strip())

        net_str = s.get("NetIO", "0B / 0B")
        net_parts = net_str.split("/")
        rx_total = _parse_bytes(net_parts[0].strip()) if net_parts else 0
        tx_total = _parse_bytes(net_parts[1].strip()) if len(net_parts) > 1 else 0

        new_net_totals[name] = {"rx": rx_total, "tx": tx_total}
        prev = _prev_net_totals.get(name, {"rx": rx_total, "tx": tx_total})
        net_rx = max(0, rx_total - prev["rx"])
        net_tx = max(0, tx_total - prev["tx"])

        if stack_name not in result:
            result[stack_name] = {"cpu_percent": 0.0, "memory_mb": 0.0, "net_rx": 0, "net_tx": 0}

        entry = result[stack_name]
        entry["cpu_percent"] = round(entry["cpu_percent"] + cpu, 1)
        entry["memory_mb"] = round(entry["memory_mb"] + mem_mb, 1)
        entry["net_rx"] += net_rx
        entry["net_tx"] += net_tx

    _prev_net_totals = new_net_totals
    return result


@app.get("/api/metrics")
async def metrics() -> JSONResponse:
    cached = _cache["metrics"]
    now = time.time()
    if cached["data"] and (now - cached["ts"]) < _CACHE_TTL_SECONDS:
        return JSONResponse(content=cached["data"])

    try:
        data = await _fetch_docker_stats()
    except Exception as e:
        logger.warning(f"docker stats unavailable: {e}")
        return JSONResponse(status_code=503, content={"error": "metrics unavailable"})

    _cache["metrics"] = {"ts": now, "data": data}
    return JSONResponse(content=data)


@app.get("/")
async def root() -> JSONResponse:
    """Root endpoint."""
    return JSONResponse(
        content={
            "service": "HMS Daemon",
            "version": "0.1.0",
            "endpoints": ["/api/health", "/api/dashboard", "/api/scheduler/reload"],
            "deprecated_endpoints": ["/health", "/reload"],
        }
    )


@app.post("/reload")
async def reload_jobs() -> JSONResponse:
    """
    Reload scheduler jobs.
    Useful for reloading configuration without restarting the daemon.
    """
    try:
        from hms.daemon.scheduler import reload_scheduler

        reload_scheduler()

        jobs = get_jobs_status()
        return JSONResponse(
            content={
                "status": "success",
                "message": "Jobs reloaded",
                "jobs_count": len(jobs),
            }
        )
    except Exception as e:
        logger.error(f"❌ Error reloading jobs: {e}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={
                "status": "error",
                "message": str(e),
            },
        )


@app.post("/api/scheduler/reload")
async def api_reload_jobs() -> JSONResponse:
    """Reload scheduler jobs (API namespace)."""
    return await reload_jobs()


_PROTECTED_STACKS = {"infra", "home"}


@app.post("/api/stacks/{name}/up")
async def stack_up_endpoint(name: str) -> JSONResponse:
    if not stack_metadata.stack_exists(name):
        raise HTTPException(status_code=404, detail=f"Stack '{name}' not found")
    try:
        logger.info(f"🟢 Web: starting stack '{name}'")
        if not config_manager.is_stack_enabled(name):
            config_manager.enable_stack(name)
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, docker_manager.stack_up, name)
        _cache["dashboard"] = {"ts": 0.0, "data": None}
        logger.info(f"✅ Web: stack '{name}' started")
        notify("🟢 Stack started", f"{name} (web)")
        return JSONResponse(content={"status": "ok", "stack": name, "action": "up"})
    except Exception as e:
        notify("❌ Error starting stack", f"{name} (web): {e}")
        logger.exception(f"❌ Web: error starting stack '{name}'")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/stacks/{name}/down")
async def stack_down_endpoint(name: str) -> JSONResponse:
    if not stack_metadata.stack_exists(name):
        raise HTTPException(status_code=404, detail=f"Stack '{name}' not found")
    if name in _PROTECTED_STACKS:
        raise HTTPException(status_code=403, detail=f"Stack '{name}' is protected")
    try:
        logger.info(f"🔴 Web: stopping stack '{name}'")
        if config_manager.is_stack_enabled(name):
            config_manager.disable_stack(name)
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, docker_manager.stack_down, name)
        _cache["dashboard"] = {"ts": 0.0, "data": None}
        logger.info(f"✅ Web: stack '{name}' stopped")
        notify("🔴 Stack stopped", f"{name} (web)")
        return JSONResponse(content={"status": "ok", "stack": name, "action": "down"})
    except Exception as e:
        notify("❌ Error stopping stack", f"{name} (web): {e}")
        logger.exception(f"❌ Web: error stopping stack '{name}'")
        raise HTTPException(status_code=500, detail=str(e))
