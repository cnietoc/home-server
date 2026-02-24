"""
Plugin: system reload-jobs
Recarga los jobs del scheduler HMS desde la configuración actual.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin

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
        # Lanza una llamada al scheduler para recargar los jobs via API
        import requests

        try:
            scheduler_url = "http://localhost:8080/api/scheduler/reload"  # Ajustar si el scheduler está en otra URL/puerto
            response = requests.post(scheduler_url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                logger.debug(f"Response data: {data}")
                jobs_count = data.get("jobs_count", 0)
                logger.info(f"✅ Jobs recargados exitosamente. Total de jobs: {jobs_count}")
                return 0
            else:
                logger.error(
                    f"❌ Error recargando jobs. Código de estado: {response.status_code}, Respuesta: {response.text}")
                return 1
        except Exception as e:
            logger.error(f"❌ Excepción al recargar jobs: {e}", exc_info=True)
            return 1
