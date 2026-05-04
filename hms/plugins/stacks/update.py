"""
Plugin: update stack
Pulls latest images and recreates containers.
"""

import logging
from typing import List

from hms.core.plugin import StackPlugin, EmptyStackBehavior
from hms.lib.docker import docker_manager

logger = logging.getLogger(__name__)


class UpdatePlugin(StackPlugin):
    """Pull latest images and recreate containers for a stack."""

    def get_name(self) -> str:
        return "update"

    def get_description(self) -> str:
        return "Pull latest images and recreate containers"

    def get_help(self) -> str:
        return """
update - Pull latest images and recreate containers

USAGE:
  hms update STACK

DESCRIPTION:
  Pulls the latest images for the stack and recreates containers.
  If the stack is stopped, pulls only without restarting.
"""

    def get_empty_stack_behavior(self) -> EmptyStackBehavior:
        return EmptyStackBehavior.ENABLED

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        from hms.lib.notify import send as notify

        was_running = docker_manager.get_stack_status(stack_name) not in ("stopped", "not-found")

        logger.info(f"⬇️  Pulling latest images for '{stack_name}'...")
        pull_result, has_updates = docker_manager.stack_pull(stack_name)

        if pull_result != 0:
            logger.error(f"❌ Failed to pull images for '{stack_name}'")
            return pull_result

        if not has_updates:
            logger.info(f"✅ Stack '{stack_name}' is already up to date")
            return 0

        if not was_running:
            logger.info(f"✅ Images updated for '{stack_name}' (stack was stopped, not restarted)")
            notify(f"⬆️ HMS: {stack_name} actualizado", "Nuevas imágenes descargadas (stack parado, no reiniciado)")
            return 0

        logger.info(f"🔄 Recreating containers for '{stack_name}'...")
        up_result = docker_manager.stack_up(stack_name)

        if up_result != 0:
            logger.error(f"❌ Failed to recreate containers for '{stack_name}'")
            return up_result

        logger.info(f"⏳ Waiting for '{stack_name}' to be healthy...")
        healthy = docker_manager.wait_for_healthy(stack_name)
        if healthy:
            logger.info(f"✅ Stack '{stack_name}' updated and healthy")
            notify(f"⬆️ HMS: {stack_name} actualizado", "Nuevas imágenes desplegadas ✅")
        else:
            logger.warning(f"⚠️  Stack '{stack_name}' updated but health check failed or timed out")
            notify(f"⬆️ HMS: {stack_name} actualizado", "Imágenes desplegadas ⚠️ health check fallido")

        from hms.lib.router import apply_port_forwards_for_stack
        apply_port_forwards_for_stack(stack_name)

        return up_result
