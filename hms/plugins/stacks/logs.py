"""
Plugin: show stack logs
Display logs from a stack using docker compose logs.
Supports passing all docker compose logs arguments (-f, --until, etc).
"""

import logging
from typing import List

from hms.core.plugin import StackPlugin, EmptyStackBehavior
from hms.lib.docker import docker_manager

logger = logging.getLogger(__name__)


class LogsPlugin(StackPlugin):
    """Show logs from a stack."""

    def get_name(self) -> str:
        return "logs"

    def get_description(self) -> str:
        return "Show logs from a stack"

    def get_help(self) -> str:
        return """
logs - Show logs from a stack

USAGE:
  hms [STACK] logs [OPTIONS] [SERVICE...]
  
DESCRIPTION:
  Display logs from a stack, supporting all docker compose logs options.
  
EXAMPLES:
  hms mystack logs                    # Show all logs
  hms mystack logs -f                 # Follow logs
  hms mystack logs -f --tail=100      # Follow last 100 lines
  hms mystack logs service1 service2  # Show logs from specific services
  hms mystack logs --until=10m        # Show logs until 10 minutes ago
  hms mystack logs --timestamps       # Include timestamps

SUPPORTED OPTIONS:
  -f, --follow           Follow log output
  --tail=LINES           Number of lines to show from the end (default: all)
  --timestamps           Show timestamps
  --until=TIME           Show logs until (e.g., 10m, 2h)
  --since=TIME           Show logs since (e.g., 10m, 2h)
  --no-color             Disable colored output
  --index=N              Index of the service replica to view logs for
"""

    def get_empty_stack_behavior(self) -> EmptyStackBehavior:
        return EmptyStackBehavior.ERROR

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        """Execute plugin."""
        try:
            result = docker_manager.stack_logs(stack_name, args)
            return result
        except Exception as e:
            logger.error(f"❌ Error retrieving logs for stack '{stack_name}': {e}")
            return 1


