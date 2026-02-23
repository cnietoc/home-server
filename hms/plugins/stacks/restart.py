"""
Plugin: restart stacks
Restarts a stack (down then up).
"""

import logging
from typing import List

from hms.core.plugin import StackPlugin, EmptyStackBehavior
from hms.lib.config import config_manager
from hms.lib.docker import docker_manager

logger = logging.getLogger(__name__)


class RestartPlugin(StackPlugin):
    """Restart a stack."""

    def get_name(self) -> str:
        return "restart"

    def get_description(self) -> str:
        return "Restart a stack"

    def get_help(self) -> str:
        return """
restart - Restart a stack

USAGE:
  hms [STACK] restart
  
DESCRIPTION:
  Restarts the specified stack by stopping it and then starting it again.
  This is useful for applying configuration changes or recovering from issues.
"""

    def get_empty_stack_behavior(self) -> EmptyStackBehavior:
        return EmptyStackBehavior.ENABLED

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        """Execute plugin."""

        logger.info(f"🔄 Restarting stack '{stack_name}'...")

        # First, stop the stack
        logger.info(f"🔴 Stopping stack '{stack_name}'...")
        down_result = docker_manager.stack_down(stack_name)

        if down_result != 0:
            logger.error(f"❌ Failed to stop stack '{stack_name}' during restart")
            return down_result

        logger.info(f"✅ Stack '{stack_name}' stopped successfully")

        # Then, start it again
        logger.info(f"🟢 Starting stack '{stack_name}'...")

        missing_config = config_manager.check_missing_stack_config(stack_name)
        if missing_config:
            logger.error(f"❌ Cannot restart stack '{stack_name}'. Missing required configuration:")
            for item in missing_config:
                logger.error(f" - {item}")
            return 1

        enabled = config_manager.is_stack_enabled(stack_name)
        if not enabled:
            config_manager.enable_stack(stack_name)

        up_result = docker_manager.stack_up(stack_name)

        if up_result == 0:
            logger.info(f"✅ Stack '{stack_name}' restarted successfully")
        else:
            logger.error(f"❌ Failed to start stack '{stack_name}' during restart")

        return up_result

