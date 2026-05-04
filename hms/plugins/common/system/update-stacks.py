"""
Plugin: system update-stacks
Updates all enabled stacks (except infra) that are currently running.
"""

import logging

from hms.core.plugin import GlobalPlugin
from hms.lib import ui
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
update-stacks - Update all enabled stacks

USAGE:
  hms system update-stacks

DESCRIPTION:
  Pulls the latest images for all enabled stacks (except infra)
  and recreates the containers that were running.
"""

    def run(self, args: list) -> int:
        from hms.plugins.stacks.update import UpdatePlugin

        stacks = [
            s for s in stack_metadata.list_stacks()
            if s != "infra" and config_manager.is_stack_enabled(s)
        ]

        if not stacks:
            ui.info("ℹ️  No enabled stacks to update")
            return 0

        ui.info(f"🔄 Updating {len(stacks)} stack(s): {', '.join(stacks)}")

        updater = UpdatePlugin()
        failed = []

        for stack in stacks:
            result = updater.run_for_stack(stack, [])
            if result != 0:
                failed.append(stack)

        if failed:
            ui.warn(f"Failed: {', '.join(failed)}")
            logger.warning("update-stacks: failed %s", ", ".join(failed))
            return 1

        return 0
