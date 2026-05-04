"""
Plugin: system reload-jobs
Reloads HMS scheduler jobs from the current configuration.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib import ui

logger = logging.getLogger(__name__)


class ReloadJobsPlugin(GlobalPlugin):
    """Reloads HMS scheduler jobs from the current configuration."""

    def get_name(self) -> str:
        return "reload-jobs"

    def get_description(self) -> str:
        return "Reload HMS scheduler jobs from the current configuration"

    def get_help(self) -> str:
        return """
Reload Jobs - Reload HMS scheduler jobs from the current configuration

USAGE:
  hms system reload-jobs

DESCRIPTION:
  Reloads HMS scheduler jobs based on the current configuration. Useful for applying
  job configuration changes without restarting the HMS server.

EXAMPLES:
  hms system reload-jobs                    # Reload HMS scheduler jobs
"""

    def run(self, args: List[str]) -> int:
        """Execute plugin."""
        import requests

        try:
            response = requests.post("http://localhost:8080/api/scheduler/reload", timeout=10)
            if response.status_code == 200:
                data = response.json()
                logger.debug("Response data: %s", data)
                jobs_count = data.get("jobs_count", 0)
                ui.ok(f"Jobs reloaded successfully. Total jobs: {jobs_count}")
                return 0
            else:
                ui.err(f"Error reloading jobs. Status code: {response.status_code}")
                logger.error("reload-jobs: HTTP %d — %s", response.status_code, response.text)
                return 1
        except Exception:
            logger.exception("❌ Exception while reloading jobs")
            return 1
