"""
Base plugin class for HMS plugin system.
All plugins inherit from this class.
"""

from abc import ABC, abstractmethod
from typing import List


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

