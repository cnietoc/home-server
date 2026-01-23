"""
Scheduler para tareas automáticas del sistema.
Usa APScheduler para ejecutar jobs periódicos directamente como plugins del CLI.
"""

import logging
import time
from datetime import datetime
from typing import Optional, Dict, Any

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.date import DateTrigger
from apscheduler.triggers.interval import IntervalTrigger

from hms.lib.config import config_manager
from hms.lib.interval import parse_interval, format_interval
from hms.lib.plugin_loader import get_plugin_loader

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
        else:
            logger.info(f"✅ Job {job_id} ok ({plugin_spec}) en {format_interval(int(duration))}")
        return result
    except Exception as e:
        duration = time.time() - start
        logger.error(f"❌ Error ejecutando job {job_id} ({plugin_spec}): {e}")
        return 1


def _load_jobs(scheduler: BackgroundScheduler):
    job_definitions = config_manager.get_job_definitions()

    current_jobs = scheduler.get_jobs()

    logger.debug(f"Actualmente hay {len(current_jobs)} job(s) en el scheduler: {[job.id for job in current_jobs]}")
    global _is_startup

    for job_definition in job_definitions:

        enabled = job_definition.enabled
        if not enabled:
            logger.info(f"⏸️ Job {job_definition.name} deshabilitado")
            continue

        plugin_spec = job_definition.plugin
        if not plugin_spec:
            logger.warning(f"⚠️ Job {job_definition.name} sin plugin, skipeado")
            continue

        args = job_definition.args

        triggers = job_definition.triggers or {}

        if not triggers:
            logger.warning(f"⚠️ Job {job_definition.name} sin triggers, skipeado")
            continue

        for trigger in triggers:
            skip = False
            if not trigger.value:
                logger.warning(
                    f"❌ Trigger inválido para job {job_definition.name}: tipo '{trigger.type}' sin valor: {trigger.config}")
                continue
            if trigger.type == "startup":
                seconds = parse_interval(trigger.value)
                job_id = f"{job_definition.name}-on-startup-{seconds}s"
                trigger = DateTrigger(run_date=datetime.fromtimestamp(time.time() + seconds))
                if not _is_startup:
                    logger.debug(f"⏭️ Skipping startup trigger for job {job_definition.name} on reload")
                    skip = True
            elif trigger.type == "interval":
                seconds = parse_interval(trigger.value)
                if seconds is None:
                    logger.warning(
                        f"❌ Trigger inválido para job {job_definition.name}: intervalo inválido: {trigger.value}")
                    continue
                job_id = f"{job_definition.name}-interval-{seconds}s"
                trigger = IntervalTrigger(seconds=seconds)
            elif trigger.type == "cron":
                job_id = f"{job_definition.name}-cron-{trigger.value}"
                try:
                    trigger = CronTrigger.from_crontab(trigger.value)
                except Exception as e:
                    logger.warning(f"❌ Trigger inválido para job {job_definition.name}: {e}")
                    continue
            else:
                logger.warning(f"❌ Trigger inválido para job {job_definition.name}: tipo desconocido: {type}")
                continue
            if not skip:
                scheduler.add_job(
                    func=_run_plugin,
                    args=[job_id, plugin_spec, args],
                    trigger=trigger,
                    id=job_id,
                    name=job_definition.description,
                    replace_existing=True
                )
                logger.info(f"✅ Job {job_id} registrado: {trigger}")

            current_jobs = [job for job in current_jobs if job.id != job_id]

    logger.debug(f"Quedan {len(current_jobs)} job(s) sin definir: {[job.id for job in current_jobs]}")

    # Remover jobs que ya no están en la configuración
    for job in current_jobs:
        scheduler.remove_job(job.id)
        logger.info(f"🗑️ Job {job.id} eliminado (ya no está en configuración)")

    _is_startup = False


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
        _load_jobs(_scheduler)
        logger.info("📝 Scheduler configurado con jobs")

    return _scheduler


def reload_scheduler():
    """Recargar jobs desde state y reconfigurar scheduler (sin ejecutar startup_triggers)."""
    scheduler = _get_scheduler()
    _load_jobs(scheduler)
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
