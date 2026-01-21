"""
Scheduler para tareas automáticas del sistema.
Usa APScheduler para ejecutar jobs periódicos directamente como plugins del CLI.
"""

import logging
import time
from typing import Optional, Dict, Any
from datetime import datetime

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.date import DateTrigger

from hms.lib.jobs_defaults import get_default_jobs
from hms.lib.state import get_state_manager
from hms.lib.plugin_loader import get_plugin_loader
from hms.lib.interval import parse_interval, format_interval

logger = logging.getLogger(__name__)

# Control de startup vs reload
_is_startup = True


def _build_trigger(config: Dict[str, Any]):
    """
    Construir trigger cron o interval.

    Soporta:
    - Cron: {"type": "cron", "expression": "0 */6 * * *"}
    - Interval natural: {"type": "interval", "interval": "30m"} o {"interval": "2h"}
    - Interval legacy: {"minutes": 30, "hours": 2, "seconds": 45}

    Default: 30m si no se especifica.
    """
    trigger = config.get("trigger", {})
    ttype = trigger.get("type", "interval")

    if ttype == "cron":
        expr = trigger.get("expression")
        if not expr:
            raise ValueError("Cron trigger sin 'expression'")
        return CronTrigger.from_crontab(expr)

    # Parseo de interval
    # 1. Intentar intervalo natural (nueva forma)
    interval_str = trigger.get("interval")
    if interval_str:
        seconds = parse_interval(interval_str)
        if seconds is None:
            raise ValueError(f"Intervalo inválido: {interval_str}")
        return IntervalTrigger(seconds=seconds)

    # 2. Intentar forma legacy (minutos, horas, segundos)
    minutes = trigger.get("minutes")
    hours = trigger.get("hours")
    seconds = trigger.get("seconds")
    if any([minutes, hours, seconds]):
        return IntervalTrigger(minutes=minutes or 0, hours=hours or 0, seconds=seconds or 0)

    # 3. Default: 30 minutos
    return IntervalTrigger(minutes=30)


def _record_run(job_id: str, status: str, message: str = "", duration_seconds: float = 0) -> None:
    """
    Persistir resultado de ejecución de un job.

    Guarda tanto timestamp unix como formato legible (ISO 8601).
    """
    state = get_state_manager()
    now = int(time.time())
    now_iso = datetime.fromtimestamp(now).isoformat()

    state.set(
        f"daemon.jobs.{job_id}.last_run",
        {
            "timestamp": now,
            "datetime": now_iso,
            "status": status,
            "duration": round(duration_seconds, 2),
            "duration_formatted": format_interval(int(duration_seconds)),
            "message": message,
        },
    )


def _run_plugin(job_id: str, plugin_spec: str, args: list = None) -> int:
    """
    Ejecutar un plugin del CLI directamente (sin subprocess).

    Args:
        job_id: ID del job (para logging)
        plugin_spec: Especificación del plugin (ej: "system:update-dns")
        args: Argumentos adicionales para pasar al plugin

    Returns:
        Código de salida del plugin (0 = éxito)
    """
    if args is None:
        args = []

    start = time.time()
    try:
        loader = get_plugin_loader()

        # Resolver path del plugin
        if ":" in plugin_spec:
            parts = plugin_spec.split(":", 1)
            cat, cmd = parts
            globals_plugins = loader.discover_globals()
            if cat in globals_plugins and isinstance(globals_plugins[cat], dict):
                if cmd in globals_plugins[cat]:
                    plugin_path = globals_plugins[cat][cmd]
                else:
                    raise ValueError(f"Subcomando no encontrado: {cmd}")
            else:
                raise ValueError(f"Categoría no encontrada: {cat}")
        else:
            # Intentar primero en stacks, luego en globals
            stacks_plugins = loader.discover_stacks()
            globals_plugins = loader.discover_globals()

            if plugin_spec in stacks_plugins:
                plugin_path = stacks_plugins[plugin_spec]
            elif plugin_spec in globals_plugins and isinstance(globals_plugins[plugin_spec], str):
                plugin_path = globals_plugins[plugin_spec]
            else:
                raise ValueError(f"Plugin no encontrado: {plugin_spec}")

        # Cargar y ejecutar
        plugin = loader.load(plugin_path)
        if not plugin:
            raise ValueError(f"No se pudo cargar: {plugin_spec}")

        result = plugin.run(args)
        duration = time.time() - start

        if result != 0:
            logger.warning(f"⚠️  Job {job_id} falló ({plugin_spec}) en {format_interval(int(duration))}")
            _record_run(job_id, "error", f"Plugin returned {result}", duration)
        else:
            logger.info(f"✅ Job {job_id} ok ({plugin_spec}) en {format_interval(int(duration))}")
            _record_run(job_id, "success", "", duration)
        return result
    except Exception as e:
        duration = time.time() - start
        logger.error(f"❌ Error ejecutando job {job_id} ({plugin_spec}): {e}")
        _record_run(job_id, "error", str(e), duration)
        return 1


def _schedule_job(scheduler: BackgroundScheduler, job_id: str, cfg: Dict[str, Any], is_startup: bool = True):
    """
    Registrar un job en el scheduler con validaciones básicas.

    Args:
        scheduler: Instancia del scheduler
        job_id: ID del job
        cfg: Configuración del job
        is_startup: True si se está llamando al arrancar, False en reload
    """
    global _is_startup

    enabled = cfg.get("enabled", True)
    if not enabled:
        logger.info(f"⏸️  Job {job_id} deshabilitado")
        return

    plugin_spec = cfg.get("plugin")
    if not plugin_spec:
        logger.warning(f"⚠️  Job {job_id} sin plugin, skipeado")
        return

    # Parámetros adicionales para pasar al plugin
    args = cfg.get("args", [])

    # Si hay startup_trigger y es startup (no reload), ejecutar con DateTrigger
    startup_trigger_cfg = cfg.get("startup_trigger")
    if startup_trigger_cfg and is_startup:
        delay_seconds = startup_trigger_cfg.get("delay_seconds", 0)
        run_time = datetime.fromtimestamp(time.time() + delay_seconds)

        startup_job_id = f"__startup__{job_id}"
        startup_trigger = DateTrigger(run_date=run_time)

        scheduler.add_job(
            lambda spec=plugin_spec, jid=job_id, job_args=args: _run_plugin(jid, spec, job_args),
            trigger=startup_trigger,
            id=startup_job_id,
            name=f"{cfg.get('meta', {}).get('description', job_id)} [STARTUP]",
            replace_existing=True,
            misfire_grace_time=300,
        )
        logger.info(f"🚀 Job {job_id} registrado para startup en {delay_seconds}s")

    # Registrar el job periódico si tiene trigger normal
    if cfg.get("trigger"):
        try:
            trigger = _build_trigger(cfg)
        except Exception as e:
            logger.error(f"❌ Trigger inválido para job {job_id}: {e}")
            return

        scheduler.add_job(
            lambda spec=plugin_spec, jid=job_id, job_args=args: _run_plugin(jid, spec, job_args),
            trigger=trigger,
            id=job_id,
            name=cfg.get("meta", {}).get("description", job_id),
            replace_existing=True,
            misfire_grace_time=300,
        )
        logger.info(f"✅ Job {job_id} registrado: {trigger}")


def _load_jobs_from_state(scheduler: BackgroundScheduler, is_startup: bool = True):
    state = get_state_manager()
    jobs_cfg = state.get_jobs_config()
    if not jobs_cfg:
        jobs_cfg = get_default_jobs()
        state.set("daemon.jobs", jobs_cfg)

    for job in scheduler.get_jobs():
        scheduler.remove_job(job.id)

    for job_id, cfg in jobs_cfg.items():
        _schedule_job(scheduler, job_id, cfg, is_startup=is_startup)


# Instancia global del scheduler
_scheduler: Optional[BackgroundScheduler] = None


def _get_scheduler() -> BackgroundScheduler:
    """
    Obtener instancia global del scheduler.
    Inicializa con jobs configurados si es la primera vez.
    """
    global _scheduler

    if _scheduler is None:
        _scheduler = BackgroundScheduler(
            daemon=True,
            max_instances=1,
        )
        _load_jobs_from_state(_scheduler, is_startup=True)
        logger.info("📝 Scheduler configurado con jobs")

    return _scheduler


def reload_scheduler():
    """Recargar jobs desde state y reconfigurar scheduler (sin ejecutar startup_triggers)."""
    scheduler = _get_scheduler()
    _load_jobs_from_state(scheduler, is_startup=False)
    logger.info(f"🔄 Scheduler recargado ({len(scheduler.get_jobs())} job(s))")


def start_scheduler() -> None:
    """Iniciar scheduler."""
    scheduler = _get_scheduler()
    if not scheduler.running:
        scheduler.start()
        logger.info(f"🚀 Scheduler iniciado con {len(scheduler.get_jobs())} job(s)")
    else:
        logger.debug("Scheduler ya está corriendo")


def stop_scheduler() -> None:
    """Detener scheduler."""
    global _scheduler
    if _scheduler and _scheduler.running:
        _scheduler.shutdown(wait=True)
        logger.info("🛑 Scheduler detenido")
        _scheduler = None


def get_jobs_status() -> list:
    """Obtener estado de todos los jobs."""
    scheduler = _get_scheduler()
    return [
        {
            "id": job.id,
            "name": job.name,
            "trigger": str(job.trigger),
            "next_run": str(job.next_run_time) if hasattr(job, 'next_run_time') and job.next_run_time else "never",
        }
        for job in scheduler.get_jobs()
    ]

def check_scheduler_running() -> bool:
    """Verificar si el scheduler está corriendo."""
    scheduler = _get_scheduler()
    return scheduler.running
