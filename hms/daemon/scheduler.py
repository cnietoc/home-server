"""
Scheduler para tareas automáticas del sistema.
Usa APScheduler para ejecutar jobs periódicos como actualización de DNS cada 30 minutos.
"""

import logging
import subprocess
import time
from typing import Optional, Dict, Any

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from hms.lib.jobs_defaults import get_default_jobs
from hms.lib.state import get_state_manager

logger = logging.getLogger(__name__)


def _build_trigger(config: Dict[str, Any]):
    """Construir trigger cron o interval; default 30m interval."""
    trigger = config.get("trigger", {})
    ttype = trigger.get("type", "interval")
    if ttype == "cron":
        expr = trigger.get("expression")
        if not expr:
            raise ValueError("Cron trigger sin 'expression'")
        return CronTrigger.from_crontab(expr)

    minutes = trigger.get("minutes")
    hours = trigger.get("hours")
    seconds = trigger.get("seconds")
    if not any([minutes, hours, seconds]):
        minutes = 30
    return IntervalTrigger(minutes=minutes or 0, hours=hours or 0, seconds=seconds or 0)


def _record_run(job_id: str, status: str, message: str = "") -> None:
    """Persistir resultado de ejecución de un job."""
    state = get_state_manager()
    now = int(time.time())
    state.set(
        f"daemon.jobs.{job_id}.last_run",
        {
            "timestamp": now,
            "status": status,
            "message": message,
        },
    )


def _run_command(job_id: str, cmd: list) -> int:
    start = time.time()
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        duration = round(time.time() - start, 2)
        if result.returncode != 0:
            stderr = (result.stderr or '').strip()
            logger.warning(f"⚠️  Job {job_id} fallo ({cmd}) en {duration}s: {stderr}")
            _record_run(job_id, "error", stderr)
        else:
            logger.info(f"✅ Job {job_id} ok ({cmd}) en {duration}s")
            _record_run(job_id, "success")
        return result.returncode
    except Exception as e:
        logger.error(f"❌ Error ejecutando job {job_id} ({cmd}): {e}")
        _record_run(job_id, "error", str(e))
        return 1


def _schedule_job(scheduler: BackgroundScheduler, job_id: str, cfg: Dict[str, Any]):
    """Registrar un job en el scheduler con validaciones básicas."""
    enabled = cfg.get("enabled", True)
    if not enabled:
        logger.info(f"⏸️  Job {job_id} deshabilitado")
        return

    command = cfg.get("command")
    if not command:
        logger.warning(f"⚠️  Job {job_id} sin comando, skipeado")
        return

    try:
        trigger = _build_trigger(cfg)
    except Exception as e:
        logger.error(f"❌ Trigger inválido para job {job_id}: {e}")
        return

    scheduler.add_job(
        lambda cmd=command, jid=job_id: _run_command(jid, cmd),
        trigger=trigger,
        id=job_id,
        name=cfg.get("meta", {}).get("description", job_id),
        replace_existing=True,
        misfire_grace_time=300,
    )
    logger.info(f"✅ Job {job_id} registrado: {trigger}")


def _load_jobs_from_state(scheduler: BackgroundScheduler):
    state = get_state_manager()
    jobs_cfg = state.get_jobs_config()
    if not jobs_cfg:
        jobs_cfg = get_default_jobs()
        state.set("daemon.jobs", jobs_cfg)

    for job in scheduler.get_jobs():
        scheduler.remove_job(job.id)

    for job_id, cfg in jobs_cfg.items():
        _schedule_job(scheduler, job_id, cfg)


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
        _load_jobs_from_state(_scheduler)
        logger.info("📝 Scheduler configurado con jobs")

    return _scheduler


def reload_scheduler():
    """Recargar jobs desde state y reconfigurar scheduler."""
    scheduler = _get_scheduler()
    _load_jobs_from_state(scheduler)
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
