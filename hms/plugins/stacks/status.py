"""
Plugin: status
Show status of a stack (running containers, health, etc.)
"""

import subprocess
from typing import List

from hms.core.plugin import StackPlugin
from hms.lib.stacks import get_stack_manager


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
            print(f"❌ Stack not found: {stack_name}")
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
                print(f"❌ Failed to get status for {stack_name}")
                if result.stderr:
                    print(result.stderr)
                return result.returncode

            if not quiet:
                print(f"\n📊 Stack: {stack_name}\n")

            print(result.stdout)

            return 0

        except FileNotFoundError:
            print("❌ Docker or docker compose not found. Is Docker installed?")
            return 1
        except Exception as e:
            print(f"❌ Error: {e}")
            return 1

