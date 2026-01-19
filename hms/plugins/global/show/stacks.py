"""
Plugin: show stacks
Lists all available stacks with their descriptions.
"""

from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib.stacks import get_stack_manager


class ShowStacksPlugin(GlobalPlugin):
    """Show all available stacks."""

    def get_name(self) -> str:
        return "stacks"

    def get_description(self) -> str:
        return "List all available stacks"

    def get_help(self) -> str:
        return """
Show Stacks - List all available stacks

USAGE:
  hms show stacks

DESCRIPTION:
  Displays all available stacks found in docker/ directory
  with their descriptions from config/stacks.yml (if available).
"""

    def run(self, args: List[str]) -> int:
        """Execute plugin."""
        stack_manager = get_stack_manager()
        stacks = stack_manager.list_all_stacks()

        if not stacks:
            print("ℹ️  No stacks found in docker/")
            return 0

        # Print stacks
        print(f"\n📦 Available Stacks ({len(stacks)}):\n")

        for stack in stacks:
            predeploy_icon = "🔧" if stack['has_predeploy'] else "  "
            print(f"{predeploy_icon} {stack['name']:<15} {stack['description']}")

        print(f"\n🔧 = Has pre-deploy script\n")

        return 0

