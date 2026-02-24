"""
Mini API REST para el daemon HMS.
Expone endpoints bajo /api y mantiene legacy para compatibilidad.
Integra el scheduler APScheduler en el ciclo de vida de FastAPI.
"""

import logging
import time
from contextlib import asynccontextmanager
import os

from fastapi import FastAPI
from fastapi.responses import JSONResponse

from hms.daemon.scheduler import (
    check_scheduler_running,
    get_jobs_status,
    start_scheduler,
    stop_scheduler,
)
from hms.lib.docker import docker_manager
from hms.lib.stacks import stack_metadata
from hms.lib.config import config_manager

logger = logging.getLogger(__name__)

# Variables globales para tracking
_start_time = time.time()
_cache = {"dashboard": {"ts": 0.0, "data": None}}
_CACHE_TTL_SECONDS = int(os.environ.get("HMS_DASHBOARD_TTL", "10"))


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Gestión del ciclo de vida de la aplicación.
    Inicia el scheduler al arrancar y lo detiene al cerrar.
    """
    # Startup
    logger.info("⏱️  Iniciando scheduler...")
    start_scheduler()

    # Mostrar jobs configurados
    jobs = get_jobs_status()
    logger.info(f"📋 Scheduler iniciado con {len(jobs)} job(s)")
    for job in jobs:
        logger.info(f"   ✓ {job['name']} ({job['id']}) - {job['trigger']}")

    yield

    # Shutdown
    logger.info("🛑 Deteniendo scheduler...")
    stop_scheduler()
    logger.info("✅ Scheduler detenido")


# Crear app FastAPI con lifespan
app = FastAPI(
    title="HMS Daemon API",
    description="API interna del daemon HMS para healthcheck",
    version="0.1.0",
    docs_url=None,  # Deshabilitar docs en producción
    redoc_url=None,
    lifespan=lifespan,
)


@app.get("/health")
async def health() -> JSONResponse:
    """
    Endpoint de healthcheck.
    Verifica que el scheduler está corriendo y devuelve estado básico.
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
                    "message": "Scheduler no está corriendo"
                }
            )

        # Contar jobs activos
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
        logger.error(f"❌ Error en healthcheck: {e}", exc_info=True)
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": str(e),
            }
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
                "status": "high" if usage_percent > 80 else "medium" if usage_percent > 60 else "low",
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
                    "description": stack_metadata.get_service_description(stack_name, service) or "",
                    "public": stack_metadata.is_service_public(stack_name, service) if has_endpoint else False,
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
    Recargar jobs del scheduler.
    Útil para recargar configuración sin reiniciar el daemon.
    """
    try:
        from hms.daemon.scheduler import reload_scheduler

        reload_scheduler()

        jobs = get_jobs_status()
        return JSONResponse(
            content={
                "status": "success",
                "message": "Jobs recargados",
                "jobs_count": len(jobs),
            }
        )
    except Exception as e:
        logger.error(f"❌ Error recargando jobs: {e}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={
                "status": "error",
                "message": str(e),
            }
        )


@app.post("/api/scheduler/reload")
async def api_reload_jobs() -> JSONResponse:
    """Reload scheduler jobs (API namespace)."""
    return await reload_jobs()
