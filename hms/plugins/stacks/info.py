"""
Plugin: show stacks
Lists all available stacks with their descriptions.
"""

import logging
from typing import List

from hms.core.plugin import StackPlugin, EmptyStackBehavior
from hms.lib.docker import docker_manager
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


class InfoPlugin(StackPlugin):
    """Show info about a stack."""

    def get_name(self) -> str:
        return "info"

    def get_description(self) -> str:
        return "Show info about a stack"

    def get_help(self) -> str:
        return """
info - Show info about a stack

USAGE:
  hms [STACK] info

DESCRIPTION:
  Displays information about the specified stack.
"""

    def get_empty_stack_behavior(self) -> EmptyStackBehavior:
        return EmptyStackBehavior.ENABLED

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        """Execute plugin."""

        description = stack_metadata.get_description(stack_name) or "No description"
        services = stack_metadata.list_services(stack_name)
        status = docker_manager.get_stack_status(stack_name)
        status_icon = {"running": "🟢",
                       "stopped": "🔴",
                          "partial": "🟠",
                            "not-found": "⚪️"}.get(status, "⚪️")


        lines: List[str] = []
        title = f"{status_icon} Stack: {stack_name}"
        lines.append("")
        lines.append(title)
        lines.append("-" * len(title))
        lines.append(f"Status: {status}")
        lines.append(f"Description: {description}")

        if services:
            lines.append("Services:")
            for service in services:
                service_description = stack_metadata.get_service_description(stack_name, service) or "No description"
                is_service_public = stack_metadata.is_service_public(stack_name, service)
                service_subdomain = stack_metadata.get_service_subdomain(stack_name, service) or "N/A"
                visibility = "public" if is_service_public else "private"

                lines.append(f"  - {service} | {service_description} | {visibility} | domain: {service_subdomain}")
        else:
            lines.append("Services: none")

        lines.append("")

        logger.info("\n".join(lines))

        return 0
