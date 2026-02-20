"""
Plugin: show stacks
Lists all available stacks with their descriptions.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


class ListPlugin(GlobalPlugin):
    """Show all available stacks."""

    def get_name(self) -> str:
        return "list"

    def get_description(self) -> str:
        return "List all available stacks"

    def get_help(self) -> str:
        return """
Show Stacks - List all available stacks

USAGE:
  hms list

DESCRIPTION:
  Displays all available stacks found in docker/ directory
  with their descriptions from config/stacks.yml (if available).
"""

    def run(self, args: List[str]) -> int:
        """Execute plugin."""
        stacks = stack_metadata.list_stacks()

        if not stacks:
            logger.info("ℹ️  No stacks found in docker/")
            return 0

        # Print stacks
        logger.info(f"📦 Available Stacks ({len(stacks)}):")
        logger.info("")

        for stack in stacks:
            predeploy_icon = "🔧" if stack_metadata.has_predeploy(stack) else "  "
            description = stack_metadata.get_description(stack) or "No description"
            logger.info(f"{predeploy_icon} {stack:<15} {description}")

        logger.info("")
        logger.info("🔧 = Has pre-deploy script")
        logger.info("")

        return 0

