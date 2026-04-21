"""
Plugin: show stacks
Lists all available stacks with their descriptions.
"""

import logging
from typing import List

from hms.core.plugin import StackPlugin, EmptyStackBehavior
from hms.lib.config import config_manager
from hms.lib.docker import docker_manager
from hms.lib.notify import send as notify

logger = logging.getLogger(__name__)


class DownPlugin(StackPlugin):
    """Down a stack."""

    def get_name(self) -> str:
        return "down"

    def get_description(self) -> str:
        return "Down a stack"

    def get_help(self) -> str:
        return """
down - Down a stack

USAGE:
  hms [STACK] down
  
DESCRIPTION:
  Downs the specified stack.
"""

    def get_empty_stack_behavior(self) -> EmptyStackBehavior:
        return EmptyStackBehavior.ALL

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        """Execute plugin."""
        enabled = config_manager.is_stack_enabled(stack_name)

        if enabled:
            config_manager.disable_stack(stack_name)

        current_status = docker_manager.get_stack_status(stack_name)

        if current_status in ['running', 'partial']:
            logger.info(f"🔴 Stopping stack '{stack_name}'...")
            result = docker_manager.stack_down(stack_name)

            if result == 0:
                logger.info(f"✅ Stack '{stack_name}' stopped successfully")
                notify("🔴 Stack parado", stack_name)
            else:
                logger.error(f"❌ Failed to stop stack '{stack_name}'")
                notify("❌ Error al parar stack", stack_name)
        else:
            logger.info(f"ℹ️  Stack '{stack_name}' is not running, nothing to stop.")
            result = docker_manager.stack_down(stack_name)
            logger.debug(f"ℹ️  Stack '{stack_name}' is already stopped")

        return result
