"""
Plugin: system update-stacks
Actualiza todos los stacks habilitados (excepto infra) que estén corriendo.
"""

import logging

from hms.core.plugin import GlobalPlugin
from hms.lib.config import config_manager
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


class UpdateStacksPlugin(GlobalPlugin):

    def get_name(self) -> str:
        return "update-stacks"

    def get_description(self) -> str:
        return "Pull latest images and recreate all running stacks (except infra)"

    def get_help(self) -> str:
        return """
update-stacks - Actualizar todos los stacks habilitados

USAGE:
  hms system update-stacks

DESCRIPTION:
  Descarga las últimas imágenes de todos los stacks habilitados (excepto infra)
  y recrea los containers que estaban corriendo.
"""

    def run(self, args: list) -> int:
        from hms.plugins.stacks.update import UpdatePlugin

        stacks = [
            s for s in stack_metadata.list_stacks()
            if s != "infra" and config_manager.is_stack_enabled(s)
        ]

        if not stacks:
            logger.info("ℹ️  No hay stacks habilitados para actualizar")
            return 0

        logger.info(f"🔄 Actualizando {len(stacks)} stack(s): {', '.join(stacks)}")

        updater = UpdatePlugin()
        failed = []

        for stack in stacks:
            result = updater.run_for_stack(stack, [])
            if result != 0:
                failed.append(stack)

        if failed:
            logger.warning(f"⚠️  Fallaron: {', '.join(failed)}")
            return 1

        return 0
