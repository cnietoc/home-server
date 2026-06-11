"""
Plugin: start
Starts the HMS server and brings up all enabled stacks.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib import ui
from hms.lib.config import config_manager
from hms.lib.docker import docker_manager
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


class StartPlugin(GlobalPlugin):
    """Starts the HMS server and brings up enabled stacks."""

    def get_name(self) -> str:
        return "start"

    def get_description(self) -> str:
        return "Start HMS server and enabled stacks"

    def get_help(self) -> str:
        return """
start - Start HMS server and enabled stacks

USAGE:
  hms start

DESCRIPTION:
  Starts the HMS server and automatically deploys all enabled stacks.

  Stack 'infra' is always started first as it provides core infrastructure.
  Other stacks are started based on their 'enabled' flag in config.toml.

  Behavior:
  - If stack is enabled and stopped → start it
  - If stack is enabled and running → reload config (docker compose up -d)
  - If stack is disabled and running → stop it
  - If stack is disabled and stopped → do nothing
"""

    def run(self, args: List[str]) -> int:
        """Execute plugin."""
        ui.info("🚀 Starting HMS server...")

        missing_config = config_manager.check_missing_global_config()
        if missing_config:
            ui.err("Cannot start HMS server. Missing required configuration:")
            for item in missing_config:
                ui.err(f" - {item}")
            return 1

        # 1. Bring up infra stack FIRST (always)
        infra_enabled = config_manager.is_stack_enabled("infra")
        if not infra_enabled:
            ui.warn("Infrastructure stack is disabled in configuration, check if this is intended.")
        else:
            ui.info("📦 Starting infrastructure stack...")
            missing_config = config_manager.check_missing_stack_config("infra")
            if missing_config:
                ui.err("Cannot start 'infra' stack. Missing required configuration:")
                for item in missing_config:
                    ui.err(f" - {item}")
                return 1
        self._ensure_stack_state("infra")

        # 2. Get list of available stacks (except infra)
        all_stacks = stack_metadata.list_stacks()
        stacks = [s for s in all_stacks if s != "infra"]

        if not stacks:
            ui.info("ℹ️  No additional stacks found")
            ui.ok("HMS server started successfully")
            return 0

        ui.info(f"📋 Found {len(stacks)} stack(s): {', '.join(stacks)}")

        # 3. Process each stack according to its configuration
        for stack_name in stacks:
            enabled = config_manager.is_stack_enabled(stack_name)

            if not enabled:
                logger.debug(
                    "⏭️  Stack '%s' is disabled, checking if needs to be stopped...", stack_name
                )
            else:
                logger.debug(
                    "⏭️  Stack '%s' is enabled, checking if needs to be started or reloaded...",
                    stack_name,
                )
                missing_config = config_manager.check_missing_stack_config(stack_name)
                if missing_config:
                    ui.err(f"Cannot start '{stack_name}' stack. Missing required configuration:")
                    for item in missing_config:
                        ui.err(f" - {item}")
                    continue

            self._ensure_stack_state(stack_name)

        ui.ok("HMS server started successfully")
        return 0

    @staticmethod
    def _ensure_stack_state(stack_name: str) -> None:
        enabled = config_manager.is_stack_enabled(stack_name)
        current_status = docker_manager.get_stack_status(stack_name)
        if enabled:
            if current_status in ["stopped", "not-found"]:
                ui.info(f"🔵 Starting stack '{stack_name}'...")
                result = docker_manager.stack_up(stack_name)
            elif current_status in ["running", "partial"]:
                ui.info(f"🔄 Stack '{stack_name}' is already running, reloading config...")
                result = docker_manager.stack_up(stack_name)
            else:
                return

            if result != 0:
                ui.err(f"Failed to start stack '{stack_name}'")
                logger.error("stack_up failed for '%s' (exit %d)", stack_name, result)
                return

            ui.info(f"⏳ Waiting for '{stack_name}' to be healthy...")
            healthy = docker_manager.wait_for_healthy(stack_name)
            if healthy:
                ui.ok(f"Stack '{stack_name}' started and healthy")
            else:
                ui.warn(f"Stack '{stack_name}' started but health check failed or timed out")
                logger.warning("Healthcheck failed/timeout for '%s'", stack_name)

            from hms.lib.router import apply_port_forwards_for_stack

            apply_port_forwards_for_stack(stack_name)

        else:
            if current_status in ["running", "partial"]:
                ui.info(f"🔴 Stopping stack '{stack_name}'...")
                result = docker_manager.stack_down(stack_name)

                if result == 0:
                    ui.ok(f"Stack '{stack_name}' stopped successfully")
                    from hms.lib.router import remove_port_forwards_for_stack

                    remove_port_forwards_for_stack(stack_name)
                else:
                    ui.err(f"Failed to stop stack '{stack_name}'")
                    logger.error("stack_down failed for '%s' (exit %d)", stack_name, result)
            else:
                logger.debug("ℹ️  Stack '%s' is already stopped", stack_name)
