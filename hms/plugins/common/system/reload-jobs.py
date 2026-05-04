"""
Plugin: system reload-jobs
Recarga los jobs del scheduler HMS desde la configuración actual.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib import ui

logger = logging.getLogger(__name__)


class ReloadJobsPlugin(GlobalPlugin):
    """Recarga los jobs del scheduler HMS desde la configuración actual."""

    def get_name(self) -> str:
        return "reload-jobs"

    def get_description(self) -> str:
        return "Recarga los jobs del scheduler HMS desde la configuración actual"

    def get_help(self) -> str:
        return """
Reload Jobs - Recarga los jobs del scheduler HMS desde la configuración actual

USAGE:
  hms system reload-jobs

DESCRIPTION:
  Recarga los jobs del scheduler HMS basándose en la configuración actual. Esto es útil para aplicar cambios en la configuración
  de jobs sin necesidad de reiniciar el servidor HMS.

EXAMPLES:
  hms system reload-jobs                    # Recarga los jobs del scheduler HMS
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
                ui.ok(f"Jobs recargados exitosamente. Total de jobs: {jobs_count}")
                return 0
            else:
                ui.err(f"Error recargando jobs. Código de estado: {response.status_code}")
                logger.error("reload-jobs: HTTP %d — %s", response.status_code, response.text)
                return 1
        except Exception:
            logger.exception("❌ Excepción al recargar jobs")
            return 1
