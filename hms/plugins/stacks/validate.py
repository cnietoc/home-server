"""
Plugin: validate stack
Validate the configuration of a stack."""

from typing import List

from hms.core.plugin import StackPlugin, EmptyStackBehavior
from hms.lib import ui
from hms.lib.config import config_manager


class ValidateStackPlugin(StackPlugin):
    """Validate the configuration of a stack."""

    def get_name(self) -> str:
        return "validate"

    def get_description(self) -> str:
        return "Validate the configuration of a stack"

    def get_help(self) -> str:
        return """
validate - Validate the configuration of a stack

USAGE:
  hms [STACK] validate
  
DESCRIPTION:
  Validates the configuration of the specified stack.
"""

    def get_empty_stack_behavior(self) -> EmptyStackBehavior:
        return EmptyStackBehavior.ENABLED

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        missing_config = config_manager.check_missing_global_config()
        if missing_config:
            ui.err("Global configuration validation failed. Missing required configuration:")
            for item in missing_config:
                ui.err(f" - {item}")
            return 1

        missing_config = config_manager.check_missing_stack_config(stack_name)
        if missing_config:
            ui.err(f"Stack '{stack_name}' validation failed. Missing required configuration:")
            for item in missing_config:
                ui.err(f" - {item}")
            return 1
        ui.ok(f"Stack '{stack_name}' configuration is valid")
        return 0
