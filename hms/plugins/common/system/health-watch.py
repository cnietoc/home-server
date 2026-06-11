"""
Plugin: system health-watch
Checks the readiness of all stacks and notifies failures/recoveries via Apprise.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib import ui
from hms.lib.docker import docker_manager
from hms.lib.monitoring import compute_health_events
from hms.lib.notify import send as notify
from hms.lib.stacks import stack_metadata
from hms.lib.state import StateManager

logger = logging.getLogger(__name__)


class HealthWatchPlugin(GlobalPlugin):
    """Monitor stack health and notify via Apprise."""

    def get_name(self) -> str:
        return "health-watch"

    def get_description(self) -> str:
        return "Check stack health and notify failures via Apprise"

    def get_help(self) -> str:
        return """
health-watch - Monitor stack health

USAGE:
  hms system health-watch

DESCRIPTION:
  Checks the readiness of every stack (containers running + healthchecks).
  Sends a notification (global.notification_url) when a stack becomes
  unhealthy and another one when it recovers.

  An alert requires two consecutive unhealthy readings, so transient
  failures during deploys do not trigger false positives. Stopped stacks
  (no containers) are ignored.

  State is persisted in data/state.yml under 'monitoring.health'.
  Runs periodically via the [jobs.health-watch] daemon job.
"""

    def run(self, args: List[str]) -> int:
        readings = {
            stack: docker_manager.get_stack_readiness(stack)
            for stack in stack_metadata.list_stacks()
        }
        logger.debug("health-watch readings: %s", readings)

        state = StateManager()
        previous = state.get("monitoring.health", {}) or {}
        events, new_state = compute_health_events(previous, readings)

        for event in events:
            if event.kind == "alert":
                ui.warn(f"Stack '{event.stack}' is unhealthy")
                notify(
                    "🔴 HMS: stack unhealthy",
                    f"Stack '{event.stack}' has unhealthy or stopped containers",
                )
            else:
                ui.ok(f"Stack '{event.stack}' recovered")
                notify(
                    "🟢 HMS: stack recovered",
                    f"Stack '{event.stack}' is healthy again",
                )

        state.set("monitoring.health", new_state)

        ready = sum(1 for r in readings.values() if r == "ready")
        tracked = len(new_state)
        ui.info(f"💓 health-watch: {ready}/{tracked} tracked stack(s) ready")
        return 0
