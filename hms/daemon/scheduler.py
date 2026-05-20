"""
Scheduler for automated system tasks.
Uses APScheduler to run periodic jobs directly as CLI plugins.
"""

import logging
import time
from datetime import datetime
from typing import Optional, Dict, Any

from apscheduler.executors.pool import ThreadPoolExecutor
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.date import DateTrigger
from apscheduler.triggers.interval import IntervalTrigger

from hms.core.plugin import StackPlugin
from hms.lib.config import config_manager
from hms.lib.interval import parse_interval, format_interval
from hms.lib.notify import send as notify
from hms.lib.plugin_loader import get_plugin_loader
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)

# Startup vs reload control flag
_is_startup = True


def _build_trigger(config: Dict[str, Any]):
    """
    Build a cron or interval trigger.

    Supports:
    - Cron: {"type": "cron", "expression": "0 */6 * * *"}
    - Natural interval: {"type": "interval", "interval": "30m"} or {"interval": "2h"}
    - Legacy interval: {"minutes": 30, "hours": 2, "seconds": 45}

    Default: 30m if not specified.
    """
    trigger = config.get("trigger", {})
    ttype = trigger.get("type", "interval")

    if ttype == "cron":
        expr = trigger.get("expression")
        if not expr:
            raise ValueError("Cron trigger missing 'expression'")
        return CronTrigger.from_crontab(expr)

    # Interval parsing
    # 1. Try natural interval (new form)
    interval_str = trigger.get("interval")
    if interval_str:
        seconds = parse_interval(interval_str)
        if seconds is None:
            raise ValueError(f"Invalid interval: {interval_str}")
        return IntervalTrigger(seconds=seconds)

    # 2. Try legacy form (minutes, hours, seconds)
    minutes = trigger.get("minutes")
    hours = trigger.get("hours")
    seconds = trigger.get("seconds")
    if any([minutes, hours, seconds]):
        return IntervalTrigger(minutes=minutes or 0, hours=hours or 0, seconds=seconds or 0)

    # 3. Default: 30 minutes
    return IntervalTrigger(minutes=30)


def _run_plugin(job_id: str, plugin_spec: str, args: list = None) -> int:
    """
    Run a CLI plugin directly (without subprocess).

    Args:
        job_id: Job ID (for logging)
        plugin_spec: Plugin specification (e.g. "system:update-dns")
        args: Additional arguments to pass to the plugin

    Returns:
        Plugin exit code (0 = success)
    """
    if args is None:
        args = []

    start = time.time()
    try:
        loader = get_plugin_loader()

        # Resolve plugin path
        if ":" in plugin_spec:
            parts = plugin_spec.split(":", 1)
            cat, cmd = parts
            globals_plugins = loader.discover_globals()
            if cat in globals_plugins and isinstance(globals_plugins[cat], dict):
                if cmd in globals_plugins[cat]:
                    plugin_path = globals_plugins[cat][cmd]
                else:
                    raise ValueError(f"Subcommand not found: {cmd}")
            else:
                raise ValueError(f"Category not found: {cat}")
        else:
            # Try stacks first, then globals
            stacks_plugins = loader.discover_stacks()
            globals_plugins = loader.discover_globals()

            if plugin_spec in stacks_plugins:
                plugin_path = stacks_plugins[plugin_spec]
            elif plugin_spec in globals_plugins and isinstance(globals_plugins[plugin_spec], str):
                plugin_path = globals_plugins[plugin_spec]
            else:
                raise ValueError(f"Plugin not found: {plugin_spec}")

        # Load and execute
        plugin = loader.load(plugin_path)
        if not plugin:
            raise ValueError(f"Could not load: {plugin_spec}")

        if isinstance(plugin, StackPlugin):
            available = stack_metadata.list_stacks()
            stack_names = [a for a in args if a in available]
            plugin_args = [a for a in args if a not in available]
            if stack_names:
                result = plugin.run_stacks(stack_names, plugin_args)
            else:
                result = plugin.run_all_stacks(plugin_args)
        else:
            result = plugin.run(args)
        duration = time.time() - start

        if result != 0:
            logger.warning(f"⚠️  Job {job_id} failed ({plugin_spec}) in {format_interval(int(duration))}")
            notify("❌ HMS: job failed", f"{job_id}\nPlugin: {plugin_spec}")
        else:
            logger.info(f"✅ Job {job_id} ok ({plugin_spec}) in {format_interval(int(duration))}")
        return result
    except Exception as e:
        duration = time.time() - start
        logger.error(f"❌ Error running job {job_id} ({plugin_spec}): {e}")
        notify("❌ HMS: job failed", f"{job_id}\nError: {e}")
        return 1


def _load_jobs(scheduler: BackgroundScheduler):
    job_definitions = config_manager.get_job_definitions()

    current_jobs = scheduler.get_jobs()

    logger.debug("Currently %d job(s) in the scheduler: %s", len(current_jobs), [job.id for job in current_jobs])
    global _is_startup

    for job_definition in job_definitions:

        enabled = job_definition.enabled
        if not enabled:
            logger.info(f"⏸️ Job {job_definition.name} disabled")
            continue

        plugin_spec = job_definition.plugin
        if not plugin_spec:
            logger.warning(f"⚠️ Job {job_definition.name} has no plugin, skipping")
            continue

        args = job_definition.args

        triggers = job_definition.triggers or {}

        if not triggers:
            logger.warning(f"⚠️ Job {job_definition.name} has no triggers, skipping")
            continue

        for trigger in triggers:
            skip = False
            if not trigger.value:
                logger.warning(
                    f"❌ Invalid trigger for job {job_definition.name}: type '{trigger.type}' has no value: {trigger.config}")
                continue
            if trigger.type == "startup":
                seconds = parse_interval(trigger.value)
                job_id = f"{job_definition.name}-on-startup-{seconds}s"
                trigger = DateTrigger(run_date=datetime.fromtimestamp(time.time() + seconds))
                if not _is_startup:
                    logger.debug("⏭️ Skipping startup trigger for job %s on reload", job_definition.name)
                    skip = True
            elif trigger.type == "interval":
                seconds = parse_interval(trigger.value)
                if seconds is None:
                    logger.warning(
                        f"❌ Invalid trigger for job {job_definition.name}: invalid interval: {trigger.value}")
                    continue
                job_id = f"{job_definition.name}-interval-{seconds}s"
                trigger = IntervalTrigger(seconds=seconds)
            elif trigger.type == "cron":
                job_id = f"{job_definition.name}-cron-{trigger.value}"
                try:
                    trigger = CronTrigger.from_crontab(trigger.value)
                except Exception as e:
                    logger.warning(f"❌ Invalid trigger for job {job_definition.name}: {e}")
                    continue
            else:
                logger.warning(f"❌ Invalid trigger for job {job_definition.name}: unknown type: {type}")
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

    logger.debug("Remaining %d undefined job(s): %s", len(current_jobs), [job.id for job in current_jobs])

    # Remove jobs that are no longer in the configuration
    for job in current_jobs:
        scheduler.remove_job(job.id)
        logger.info(f"🗑️ Job {job.id} removed (no longer in configuration)")

    _is_startup = False


# Global scheduler instance
_scheduler: Optional[BackgroundScheduler] = None


def _get_scheduler() -> BackgroundScheduler:
    """
    Get the global scheduler instance.
    Initialises with configured jobs on first call.
    """
    global _scheduler

    if _scheduler is None:
        _scheduler = BackgroundScheduler(
            daemon=True,
            executors={"default": ThreadPoolExecutor(max_workers=1)},
            job_defaults={
                "max_instances": 1,
                "coalesce": True,
                "misfire_grace_time": None,
            },
        )
        _load_jobs(_scheduler)
        logger.info("📝 Scheduler configured with jobs")

    return _scheduler


def reload_scheduler():
    """Reload jobs from state and reconfigure the scheduler (without running startup triggers)."""
    scheduler = _get_scheduler()
    _load_jobs(scheduler)
    logger.info(f"🔄 Scheduler reloaded ({len(scheduler.get_jobs())} job(s))")


def start_scheduler() -> None:
    """Start the scheduler."""
    scheduler = _get_scheduler()
    if not scheduler.running:
        scheduler.start()
        logger.info(f"🚀 Scheduler started with {len(scheduler.get_jobs())} job(s)")
    else:
        logger.debug("Scheduler is already running")


def stop_scheduler() -> None:
    """Stop the scheduler."""
    global _scheduler
    if _scheduler and _scheduler.running:
        _scheduler.shutdown(wait=True)
        logger.info("🛑 Scheduler stopped")
        _scheduler = None


def get_jobs_status() -> list:
    """Get the status of all jobs."""
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
    """Check whether the scheduler is running."""
    scheduler = _get_scheduler()
    return scheduler.running
