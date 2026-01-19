"""
Plugin: show stacks
Lists all available stacks with their descriptions.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib.stacks import get_stack_manager

logger = logging.getLogger(__name__)


class ShowStacksPlugin(GlobalPlugin):
    """Show all available stacks."""

    def get_name(self) -> str:
        return "stacks"

    def get_description(self) -> str:
        return "List all available stacks"

    def get_help(self) -> str:
        return """
Show Stacks - List all available stacks

USAGE:
  hms show stacks

DESCRIPTION:
  Displays all available stacks found in docker/ directory
  with their descriptions from config/stacks.yml (if available).
"""

    def run(self, args: List[str]) -> int:
        """Execute plugin."""
        stack_manager = get_stack_manager()
        stacks = stack_manager.list_all_stacks()

        if not stacks:
            logger.info("ℹ️  No stacks found in docker/")
            return 0

        # Print stacks
        logger.info(f"📦 Available Stacks ({len(stacks)}):")
        logger.info("")

        for stack in stacks:
            predeploy_icon = "🔧" if stack['has_predeploy'] else "  "
            logger.info(f"{predeploy_icon} {stack['name']:<15} {stack['description']}")

        logger.info("")
        logger.info("🔧 = Has pre-deploy script")
        logger.info("")

        return 0

