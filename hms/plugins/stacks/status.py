"""
Plugin: status
Show status of a stack (running containers, health, etc.)
"""

import subprocess
import logging
from typing import List

from hms.core.plugin import StackPlugin
from hms.lib.stacks import get_stack_manager

logger = logging.getLogger(__name__)


class StatusPlugin(StackPlugin):
    """Show status of stack containers."""

    def get_name(self) -> str:
        return "status"

    def get_description(self) -> str:
        return "Show status of stack containers"

    def get_help(self) -> str:
        return """
Status - Show container status for a stack

USAGE:
  hms [STACK] status [OPTIONS]

OPTIONS:
  --quiet, -q     Quiet mode (minimal output)

EXAMPLES:
  hms platform status
  hms media status --quiet
"""

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        """Execute plugin for a single stack."""
        stack_manager = get_stack_manager()

        if not stack_manager.stack_exists(stack_name):
            logger.error(f"Stack not found: {stack_name}")
            return 1

        stack_dir = stack_manager.get_stack_docker_dir(stack_name)

        # Parse options
        quiet = '--quiet' in args or '-q' in args

        # Run docker compose ps
        try:
            cmd = ['docker', 'compose', 'ps']
            if not quiet:
                cmd.append('--all')

            result = subprocess.run(
                cmd,
                cwd=str(stack_dir),
                capture_output=True,
                text=True
            )

            if result.returncode != 0:
                logger.error(f"Failed to get status for {stack_name}")
                if result.stderr:
                    logger.error(result.stderr)
                return result.returncode

            if not quiet:
                logger.info(f"📊 Stack: {stack_name}")

            logger.info(result.stdout)

            return 0

        except FileNotFoundError:
            logger.error("Docker or docker compose not found. Is Docker installed?")
            return 1
        except Exception as e:
            logger.error(f"Error: {e}")
            return 1

