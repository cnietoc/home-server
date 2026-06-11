"""
Plugin: show stacks
Lists all available stacks with their descriptions.
"""

import logging
from typing import List

from hms.core.plugin import StackPlugin, EmptyStackBehavior
from hms.lib import ui
from hms.lib.config import config_manager
from hms.lib.docker import docker_manager
from hms.lib.notify import send as notify
from hms.lib.router import apply_port_forwards_for_stack

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
            ui.err(f"Cannot up stack '{stack_name}'. Missing required configuration:")
            for item in missing_config:
                ui.err(f" - {item}")
            return 1

        enabled = config_manager.is_stack_enabled(stack_name)

        if not enabled:
            config_manager.enable_stack(stack_name)

        current_status = docker_manager.get_stack_status(stack_name)

        if current_status in ["stopped", "not-found"]:
            ui.info(f"🟢 Starting stack '{stack_name}'...")
            result = docker_manager.stack_up(stack_name)
        else:
            ui.info(f"🔄 Stack '{stack_name}' is already running, reloading config...")
            result = docker_manager.stack_up(stack_name)

        if result != 0:
            ui.err(f"Failed to start stack '{stack_name}'")
            logger.error(f"stack_up failed for '{stack_name}' (exit {result})")
            notify("❌ Error starting stack", stack_name)
            return result

        ui.info(f"⏳ Waiting for '{stack_name}' to be healthy...")
        healthy = docker_manager.wait_for_healthy(stack_name)
        if healthy:
            ui.ok(f"Stack '{stack_name}' is up and healthy")
            notify("🟢 Stack started", stack_name)
        else:
            ui.warn(f"Stack '{stack_name}' started but health check failed or timed out")
            logger.warning(f"Healthcheck failed/timeout for '{stack_name}'")
            notify("⚠️ Stack started (healthcheck failed)", stack_name)

        apply_port_forwards_for_stack(stack_name)

        return result
