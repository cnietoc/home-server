"""
Plugin: system disk-watch
Checks disk usage of the data volume and notifies above a threshold.
"""

import logging
import shutil
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib import ui
from hms.lib.config import config_manager
from hms.lib.monitoring import compute_disk_event
from hms.lib.notify import send as notify
from hms.lib.paths import get_data_root
from hms.lib.state import StateManager

logger = logging.getLogger(__name__)

GIB = 1024**3
DEFAULT_THRESHOLD = 85


class DiskWatchPlugin(GlobalPlugin):
    """Monitor disk usage and notify via Apprise."""

    def get_name(self) -> str:
        return "disk-watch"

    def get_description(self) -> str:
        return "Check disk usage and notify above threshold"

    def get_help(self) -> str:
        return """
disk-watch - Monitor disk usage

USAGE:
  hms system disk-watch

DESCRIPTION:
  Measures disk usage of the filesystem backing the data/ directory
  (a bind-mount of the host disk) and sends a notification via Apprise
  (global.notification_url) when usage crosses the configured threshold.

  The alert fires once; it re-arms after usage drops 5 points below the
  threshold (hysteresis, to avoid flapping).

CONFIGURATION:
  [monitoring]
  disk_threshold_percent = 85   # alert when usage >= this percentage

  State is persisted in data/state.yml under 'monitoring.disk'.
  Runs periodically via the [jobs.disk-watch] daemon job.
"""

    def run(self, args: List[str]) -> int:
        threshold = int(
            config_manager.get_config_value(
                "monitoring.disk_threshold_percent", str(DEFAULT_THRESHOLD)
            )
        )
        path = get_data_root()
        usage = shutil.disk_usage(path)
        percent = usage.used / usage.total * 100
        free_gib = usage.free / GIB

        state = StateManager()
        alerted = bool(state.get("monitoring.disk.alerted", False))
        event, new_alerted = compute_disk_event(percent, threshold, alerted)

        if event == "alert":
            ui.warn(
                f"Disk usage at {percent:.1f}% (threshold {threshold}%), "
                f"{free_gib:.1f} GiB free"
            )
            notify(
                "🔴 HMS: disk almost full",
                f"Disk usage: {percent:.1f}% (threshold {threshold}%)\n"
                f"Free: {free_gib:.1f} GiB\nPath: {path}",
            )
        elif event == "recovery":
            ui.ok(f"Disk usage back to {percent:.1f}%")
            notify(
                "🟢 HMS: disk usage recovered",
                f"Disk usage: {percent:.1f}%\nFree: {free_gib:.1f} GiB",
            )
        else:
            ui.info(f"💾 disk-watch: {percent:.1f}% used, {free_gib:.1f} GiB free")

        state.set("monitoring.disk.alerted", new_alerted)
        return 0
