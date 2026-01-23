"""
Plugin: start
Inicia el servidor HMS y levanta todos los stacks habilitados.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib.config import config_manager
from hms.lib.docker import docker_manager
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


class StartPlugin(GlobalPlugin):
    """Inicia el servidor HMS y levanta stacks habilitados."""

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
        logger.info("🚀 Starting HMS server...")

        missing_config = config_manager.check_missing_global_config()
        if missing_config:
            logger.error("❌ Cannot start HMS server. Missing required configuration:")
            for item in missing_config:
                logger.error(f" - {item}")
            return 1

        # 1. Levantar stack infra PRIMERO (siempre)
        infra_enabled = config_manager.is_stack_enabled("infra")
        if not infra_enabled:
            logger.warning("⚠️ Infrastructure stack is disabled in configuration, check if this is intended.")
        else:
            logger.info("📦 Starting infrastructure stack...")
            missing_config = config_manager.check_missing_stack_config("infra")
            if missing_config:
                logger.error("❌ Cannot start 'infra' stack. Missing required configuration:")
                for item in missing_config:
                    logger.error(f" - {item}")
                return 1
        self._ensure_stack_state("infra")

        # 2. Obtener lista de stacks disponibles (excepto infra)
        all_stacks = stack_metadata.list_stacks()
        stacks = [s for s in all_stacks if s != "infra"]

        if not stacks:
            logger.info("ℹ️  No additional stacks found")
            logger.info("✅ HMS server started successfully")
            return 0

        logger.info(f"📋 Found {len(stacks)} stack(s): {', '.join(stacks)}")

        # 3. Procesar cada stack según su configuración
        for stack_name in stacks:
            enabled = config_manager.is_stack_enabled(stack_name)

            if not enabled:
                logger.debug(f"⏭️  Stack '{stack_name}' is disabled, checking if needs to be stopped...")
            else:
                logger.debug(f"⏭️  Stack '{stack_name}' is enabled, checking if needs to be started or reloaded...")
                missing_config = config_manager.check_missing_stack_config(stack_name)
                if missing_config:
                    logger.error(f"❌ Cannot start '{stack_name}' stack. Missing required configuration:")
                    for item in missing_config:
                        logger.error(f" - {item}")
                    continue  # Saltar a la siguiente pila

            self._ensure_stack_state(stack_name)

        logger.info("✅ HMS server started successfully")
        return 0

    @staticmethod
    def _ensure_stack_state(stack_name: str) -> None:
        """
        Asegura que el stack esté en el estado deseado.

        :param stack_name: Nombre del stack
        """
        enabled = config_manager.is_stack_enabled(stack_name)
        current_status = docker_manager.get_stack_status(stack_name)
        if enabled:
            # Stack debe estar running
            if current_status in ['stopped', 'not-found']:
                logger.info(f"🔵 Starting stack '{stack_name}'...")
                result = docker_manager.stack_up(stack_name)

                if result == 0:
                    logger.info(f"✅ Stack '{stack_name}' started successfully")
                else:
                    logger.error(f"❌ Failed to start stack '{stack_name}'")

            elif current_status in ['running', 'partial']:
                logger.info(f"🔄 Stack '{stack_name}' is already running, reloading config...")
                result = docker_manager.stack_up(stack_name)

                if result == 0:
                    logger.info(f"✅ Stack '{stack_name}' reloaded successfully")
                else:
                    logger.error(f"⚠️  Failed to reload stack '{stack_name}'")

        else:
            # Stack debe estar stopped
            if current_status in ['running', 'partial']:
                logger.info(f"🔴 Stopping stack '{stack_name}'...")
                result = docker_manager.stack_down(stack_name)

                if result == 0:
                    logger.info(f"✅ Stack '{stack_name}' stopped successfully")
                else:
                    logger.error(f"❌ Failed to stop stack '{stack_name}'")
            else:
                logger.debug(f"ℹ️  Stack '{stack_name}' is already stopped")
