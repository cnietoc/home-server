"""
Plugin: stop
Stops HMS services internally (called before container stops).
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib.config import config_manager
from hms.lib.docker import docker_manager
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


class StopPlugin(GlobalPlugin):
    """Stop HMS internal services."""

    def get_name(self) -> str:
        return "stop"

    def get_description(self) -> str:
        return "Stop HMS services (internal)"

    def get_help(self) -> str:
        return """
Stop HMS Services

USAGE:
  hms stop

DESCRIPTION:
  This command is called internally before the container is stopped.
  It gracefully shuts down HMS services and saves state.
  
  Note: You should use this command from the host, not inside the container.
  The wrapper handles stopping the container automatically.
"""

    def run(self, args: List[str]) -> int:
        """Execute plugin."""
        logger.info("⏹️ Stopping HMS services...")

        all_stacks = stack_metadata.list_stacks()
        stacks = [s for s in all_stacks if s != "infra"]

        if not stacks:
            logger.info("ℹ️  No additional stacks found")
            logger.info("✅ HMS server stopped successfully")
            return 0

        logger.info(f"📋 Found {len(stacks)} stack(s): {', '.join(stacks)}")

        from hms.lib.router import remove_port_forwards_for_stack

        for stack_name in stacks:
            enabled = config_manager.is_stack_enabled(stack_name)
            if enabled:
                logger.info(f"ℹ️  Stopping stack '{stack_name}'...")
            else:
                logger.debug(f"ℹ️  Stopping disabled stack '{stack_name}'...")
            docker_manager.stack_down(stack_name)
            remove_port_forwards_for_stack(stack_name)

        logger.info("ℹ️  Stopping infrastructure stack 'infra'...")
        docker_manager.stack_down("infra")
        remove_port_forwards_for_stack("infra")

        logger.info("✅ All stacks stopped successfully")

        return 0

