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


class UpPlugin(StackPlugin):
    """Up a stack."""

    def get_name(self) -> str:
        return "up"

    def get_description(self) -> str:
        return "Up a stack"

    def get_help(self) -> str:
        return """
up - Up a stack

USAGE:
  hms [STACK] up
  
DESCRIPTION:
  Ups the specified stack.
"""

    def get_empty_stack_behavior(self) -> EmptyStackBehavior:
        return EmptyStackBehavior.ENABLED

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        """Execute plugin."""

        missing_config = config_manager.check_missing_stack_config(stack_name)
        if missing_config:
            logger.error(f"❌ Cannot up stack '{stack_name}'. Missing required configuration:")
            for item in missing_config:
                logger.error(f" - {item}")
            return 1

        enabled = config_manager.is_stack_enabled(stack_name)

        if not enabled:
            config_manager.enable_stack(stack_name)

        current_status = docker_manager.get_stack_status(stack_name)

        if current_status in ['stopped', 'not-found']:
            logger.info(f"🟢 Starting stack '{stack_name}'...")
            result = docker_manager.stack_up(stack_name)
        else:
            logger.info(f"🔄 Stack '{stack_name}' is already running, reloading config...")
            result = docker_manager.stack_up(stack_name)

        if result != 0:
            logger.error(f"❌ Failed to start stack '{stack_name}'")
            notify("❌ Error al arrancar stack", stack_name)
            return result

        logger.info(f"⏳ Waiting for '{stack_name}' to be healthy...")
        healthy = docker_manager.wait_for_healthy(stack_name)
        if healthy:
            logger.info(f"✅ Stack '{stack_name}' is up and healthy")
            notify("🟢 Stack arrancado", stack_name)
        else:
            logger.warning(f"⚠️  Stack '{stack_name}' started but health check failed or timed out")
            notify("⚠️ Stack arrancado (healthcheck fallido)", stack_name)

        return result
