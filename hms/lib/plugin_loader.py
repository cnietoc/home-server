"""
Unified plugin loader for CLI and scheduler.
"""

import importlib.util
import inspect
import logging
from pathlib import Path
from typing import Optional, Dict

from hms.core.plugin import BasePlugin, StackPlugin, GlobalPlugin

logger = logging.getLogger(__name__)


class PluginLoader:
    """Singleton for loading and caching plugins."""

    _instance = None
    _cache: Dict[str, BasePlugin] = {}

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.hms_root = Path(__file__).parent.parent
        self._initialized = True

    def load(self, plugin_path: str) -> Optional[BasePlugin]:
        """
        Load a plugin from a Python file.
        Uses automatic caching.

        Args:
            plugin_path: Path to the plugin file

        Returns:
            Plugin instance or None if loading fails
        """
        if isinstance(plugin_path, Path):
            plugin_path = str(plugin_path)

        # Return from cache if present
        if plugin_path in self._cache:
            return self._cache[plugin_path]

        try:
            spec = importlib.util.spec_from_file_location("plugin_module", plugin_path)
            if spec is None or spec.loader is None:
                return None

            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

            # Find concrete plugin class
            for name, obj in inspect.getmembers(module):
                if (inspect.isclass(obj) and
                    issubclass(obj, BasePlugin) and
                    obj not in (BasePlugin, StackPlugin, GlobalPlugin)):
                    plugin = obj()
                    self._cache[plugin_path] = plugin
                    return plugin

            return None
        except Exception as e:
            logger.error(f"Error loading plugin from {plugin_path}: {e}")
            return None

    def discover_stacks(self) -> Dict[str, str]:
        """Discover stack action plugins. {name: path}"""
        return self._scan_dir(self.hms_root / "plugins" / "stacks")

    def discover_globals(self) -> Dict[str, any]:
        """
        Discover global plugins.
        Returns: {command: path} or {command: {subcommand: path}}
        """
        common_dir = self.hms_root / "plugins" / "common"
        commands = {}

        if not common_dir.exists():
            return commands

        # Direct commands (.py files)
        for py_file in common_dir.glob("*.py"):
            if not py_file.name.startswith("_"):
                commands[py_file.stem] = str(py_file)

        # Commands with category (directories)
        for category_dir in common_dir.iterdir():
            if category_dir.is_dir() and not category_dir.name.startswith("_"):
                subcommands = self._scan_dir(category_dir)
                if subcommands:
                    commands[category_dir.name] = subcommands

        return commands

    def _scan_dir(self, directory: Path) -> Dict[str, str]:
        """Scan directory and return {name: path}"""
        plugins = {}
        if directory.exists():
            for py_file in directory.glob("*.py"):
                if not py_file.name.startswith("_"):
                    plugins[py_file.stem] = str(py_file)
        return plugins


def get_plugin_loader() -> PluginLoader:
    """Return the singleton instance."""
    return PluginLoader()
