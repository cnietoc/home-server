"""
Base plugin class for HMS plugin system.
All plugins inherit from this class.
"""

import logging
from abc import ABC, abstractmethod
from enum import Enum
from typing import List

from hms.lib.stacks import stack_metadata
from hms.lib.config import config_manager


class EmptyStackBehavior(Enum):
    """Enum for behavior when no stacks are specified."""

    ERROR = "error"  # Return error
    ALL = "all"  # Run on all stacks
    ALL_INCLUDED_INFRA = "all-including-infra"  # Run on all stacks including infra
    ENABLED = "enabled"  # Run on enabled stacks only


logger = logging.getLogger(__name__)


class BasePlugin(ABC):
    """
    Abstract base class for all HMS plugins.

    Each plugin must implement:
    - get_name(): Return plugin name
    - get_description(): Return plugin description
    - run(): Execute plugin logic
    """

    @abstractmethod
    def get_name(self) -> str:
        """Return plugin name (e.g., 'up', 'down', 'status')"""
        pass

    @abstractmethod
    def get_description(self) -> str:
        """Return plugin description"""
        pass

    @abstractmethod
    def get_help(self) -> str:
        """Return detailed help text"""
        pass

    @abstractmethod
    def run(self, args: List[str]) -> int:
        """
        Execute plugin logic.

        Args:
            args: Command line arguments

        Returns:
            Exit code (0 = success, non-zero = error)
        """
        pass


class StackPlugin(BasePlugin):
    """
    Base class for stack-specific plugins.
    Plugins that operate on stacks (up, down, status, etc.).
    """

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.available_stacks = stack_metadata.list_stacks()

    def run_stacks(self, stack_names: list[str], plugin_args):
        exit_code = 0
        logger.debug(f"Running {self.get_name()} on stacks: {stack_names}")
        for stack_name in stack_names:
            if stack_name not in self.available_stacks:
                self.logger.warning(f"Unknown stack: {stack_name}")
                exit_code = 1
                continue

            self.logger.debug(f"Executing {self.get_name()} on {stack_name}...")

            result = self.run_for_stack(stack_name, plugin_args)

            if result != 0:
                exit_code = result
        return exit_code

    @abstractmethod
    def get_empty_stack_behavior(self) -> EmptyStackBehavior:
        """
        Define behavior when no stacks are specified.
        Returns:
            EmptyStackBehavior: ERROR, ALL, or ENABLED
        """
        return EmptyStackBehavior.ERROR

    def run_all_stacks(self, plugin_args):
        """
        Execute plugin on all available stacks.
        :param plugin_args:
        :return:
        """
        if self.get_empty_stack_behavior() == EmptyStackBehavior.ERROR:
            self.logger.error(
                "No stacks specified and plugin is configured to error on empty stack list."
            )
            return 1
        elif self.get_empty_stack_behavior() == EmptyStackBehavior.ENABLED:
            enabled_stacks = [
                stack for stack in self.available_stacks if config_manager.is_stack_enabled(stack)
            ]
            if not enabled_stacks:
                self.logger.info("No enabled stacks found.")
                return 0
            return self.run_stacks(enabled_stacks, plugin_args)
        elif self.get_empty_stack_behavior() == EmptyStackBehavior.ALL_INCLUDED_INFRA:
            return self.run_stacks(self.available_stacks, plugin_args)
        else:  # EmptyStackBehavior.ALL
            stacks = [stack for stack in self.available_stacks if stack != "infra"]
            return self.run_stacks(stacks, plugin_args)

    @abstractmethod
    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        """
        Execute plugin on a single stack.

        Args:
            stack_name: Name of the stack
            args: Command line arguments

        Returns:
            Exit code (0 = success)
        """
        pass

    def run(self, args: List[str]) -> int:
        """
        Execute plugin (called by dispatcher).
        This method is called by base dispatcher.
        """
        # This will be handled by dispatcher
        pass


class GlobalPlugin(BasePlugin):
    """
    Base class for global plugins.
    Plugins that don't operate on stacks (backup, config, show, system).
    """

    pass
