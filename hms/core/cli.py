"""
HMS CLI Dispatcher
Dynamically discovers and loads plugins based on command-line arguments.
"""

import sys
import os
from pathlib import Path
from typing import List, Optional, Tuple
import importlib.util
import inspect

from hms.core.plugin import BasePlugin, StackPlugin, GlobalPlugin
from hms.lib.stacks import get_stack_manager


class CLIDispatcher:
    """
    Intelligent CLI dispatcher that:
    1. Discovers available plugins dynamically
    2. Parses command-line arguments
    3. Routes to appropriate plugin
    4. Handles both stack and global commands
    """

    def __init__(self, project_root: Optional[str] = None):
        """
        Initialize dispatcher.

        Args:
            project_root: Root directory of the project (for discovering stacks)
        """
        self.project_root = Path(project_root or os.environ.get('PROJECT_ROOT', '/project'))
        self.hms_root = Path(__file__).parent.parent
        self.plugins_cache = {}  # Cache discovered plugins
        self.verbose = False
        self.dry_run = False
        self.stack_manager = get_stack_manager(str(self.project_root))

    def discover_stacks(self) -> List[str]:
        """
        Discover available stacks by scanning docker/ directory.

        Returns:
            List of stack names
        """
        return self.stack_manager.discover_stacks()

    def discover_stack_plugins(self) -> dict:
        """
        Discover stack action plugins.

        Returns:
            Dict of {action_name: plugin_path}
        """
        return self._discover_plugins_in_dir(self.hms_root / "plugins" / "stacks")

    def discover_global_plugins(self) -> dict:
        """
        Discover global command plugins.

        Returns:
            Dict of {command_name: {subcommand: plugin_path}}
        """
        global_dir = self.hms_root / "plugins" / "global"
        commands = {}

        if global_dir.exists():
            for category_dir in global_dir.iterdir():
                if category_dir.is_dir() and not category_dir.name.startswith("_"):
                    category_name = category_dir.name
                    subcommands = self._discover_plugins_in_dir(category_dir)
                    if subcommands:
                        commands[category_name] = subcommands

        return commands

    def _discover_plugins_in_dir(self, directory: Path) -> dict:
        """
        Discover plugins in a specific directory.

        Args:
            directory: Directory to scan

        Returns:
            Dict of {plugin_name: plugin_path}
        """
        plugins = {}

        if directory.exists():
            for py_file in directory.glob("*.py"):
                if py_file.name.startswith("_"):
                    continue
                plugin_name = py_file.stem
                plugins[plugin_name] = str(py_file)

        return plugins

    def load_plugin(self, plugin_path: str) -> Optional[BasePlugin]:
        """
        Dynamically load a plugin from a Python file.

        Args:
            plugin_path: Path to plugin Python file

        Returns:
            Plugin instance or None if load fails
        """
        try:
            spec = importlib.util.spec_from_file_location("plugin_module", plugin_path)
            if spec is None or spec.loader is None:
                return None

            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

            # Find first class that inherits from BasePlugin
            for name, obj in inspect.getmembers(module):
                if (inspect.isclass(obj) and
                    issubclass(obj, BasePlugin) and
                    obj not in [BasePlugin, StackPlugin, GlobalPlugin]):
                    return obj()

            return None
        except Exception as e:
            print(f"❌ Error loading plugin from {plugin_path}: {e}", file=sys.stderr)
            return None

    def parse_args(self, args: List[str]) -> Tuple[List[str], dict]:
        """
        Parse global flags from arguments.

        Returns:
            Tuple of (remaining_args, flags_dict)
        """
        flags = {
            'verbose': False,
            'dry_run': False
        }
        remaining = []

        for arg in args:
            if arg == '--verbose' or arg == '-v':
                flags['verbose'] = True
                self.verbose = True
            elif arg == '--dry-run':
                flags['dry_run'] = True
                self.dry_run = True
            elif arg in ['-h', '--help']:
                flags['help'] = True
                remaining.append(arg)
            else:
                remaining.append(arg)

        return remaining, flags

    def is_stack_action(self, arg: str, available_stacks: List[str]) -> bool:
        """
        Determine if argument is a stack name/list or an action.

        Args:
            arg: Argument to check
            available_stacks: List of known stacks

        Returns:
            True if it's a stack name/list, False otherwise
        """
        # Check if it's a single stack
        if arg in available_stacks:
            return True

        # Check if it's comma-separated stacks
        if "," in arg:
            parts = [p.strip() for p in arg.split(",")]
            if all(p in available_stacks for p in parts):
                return True

        return False

    def dispatch(self, args: List[str]) -> int:
        """
        Main dispatch logic.

        Args:
            args: Command-line arguments (sys.argv[1:])

        Returns:
            Exit code
        """
        # Parse global flags
        args, flags = self.parse_args(args)

        if not args or flags.get('help'):
            self.print_help()
            return 0

        try:
            available_stacks = self.discover_stacks()
            stack_plugins = self.discover_stack_plugins()
            global_plugins = self.discover_global_plugins()

            # Determine if it's a stack command or global command
            first_arg = args[0]

            # Check if first arg is a stack or stack list
            if self.is_stack_action(first_arg, available_stacks):
                return self._handle_stack_command(args, available_stacks, stack_plugins)

            # Check if it's a known stack action (without stack specified = all stacks)
            elif first_arg in stack_plugins:
                return self._handle_stack_command(args, available_stacks, stack_plugins)

            # Otherwise, treat as global command
            else:
                return self._handle_global_command(args, global_plugins)

        except KeyboardInterrupt:
            print("\n⚠️  Interrupted by user")
            return 130
        except Exception as e:
            if self.verbose:
                import traceback
                traceback.print_exc()
            print(f"❌ Error: {e}", file=sys.stderr)
            return 1

    def _handle_stack_command(self, args: List[str], available_stacks: List[str],
                               stack_plugins: dict) -> int:
        """Handle stack-specific command."""
        # Parse: [stacks] <action> [args]
        stack_names = []
        action = None
        plugin_args = []

        first_arg = args[0]

        if self.is_stack_action(first_arg, available_stacks):
            # First arg is stack(s)
            stack_names = [s.strip() for s in first_arg.split(",")]
            if len(args) > 1:
                action = args[1]
                plugin_args = args[2:]
            else:
                print("❌ No action specified", file=sys.stderr)
                return 1
        else:
            # First arg is action (apply to all enabled stacks)
            stack_names = []  # Empty = all enabled
            action = args[0]
            plugin_args = args[1:]

        # Validate action exists
        if action not in stack_plugins:
            print(f"❌ Unknown action: {action}", file=sys.stderr)
            print(f"Available actions: {', '.join(stack_plugins.keys())}")
            return 1

        # Load plugin
        plugin = self.load_plugin(stack_plugins[action])
        if not plugin:
            print(f"❌ Failed to load plugin for action: {action}", file=sys.stderr)
            return 1

        # If no stacks specified, use all stacks (TODO: filter by enabled)
        if not stack_names:
            stack_names = available_stacks
            print(f"ℹ️  No stacks specified, applying to all: {', '.join(stack_names)}")

        # Execute plugin for each stack
        exit_code = 0
        for stack_name in stack_names:
            if stack_name not in available_stacks:
                print(f"⚠️  Unknown stack: {stack_name}", file=sys.stderr)
                exit_code = 1
                continue

            if self.verbose:
                print(f"🔧 Executing {action} on {stack_name}...")

            if isinstance(plugin, StackPlugin):
                result = plugin.run_for_stack(stack_name, plugin_args)
            else:
                # Fallback for plugins that don't implement StackPlugin
                result = plugin.run([stack_name] + plugin_args)

            if result != 0:
                exit_code = result

        return exit_code

    def _handle_global_command(self, args: List[str], global_plugins: dict) -> int:
        """Handle global command."""
        # Parse: <command> [subcommand] [args]
        command = args[0]

        if command not in global_plugins:
            print(f"❌ Unknown command: {command}", file=sys.stderr)
            print(f"Available commands: {', '.join(global_plugins.keys())}")
            return 1

        subcommands = global_plugins[command]

        if len(args) > 1:
            subcommand = args[1]
            plugin_args = args[2:]
        else:
            # No subcommand = show help for this command
            print(f"Available subcommands for '{command}': {', '.join(subcommands.keys())}")
            return 0

        if subcommand not in subcommands:
            print(f"❌ Unknown subcommand: {command} {subcommand}", file=sys.stderr)
            print(f"Available subcommands: {', '.join(subcommands.keys())}")
            return 1

        # Load plugin
        plugin = self.load_plugin(subcommands[subcommand])
        if not plugin:
            print(f"❌ Failed to load plugin for: {command} {subcommand}", file=sys.stderr)
            return 1

        if self.verbose:
            print(f"🔧 Executing {command} {subcommand}...")

        return plugin.run(plugin_args)

    def print_help(self) -> None:
        """Print general help text."""
        available_stacks = self.discover_stacks()
        stack_plugins = self.discover_stack_plugins()
        global_plugins = self.discover_global_plugins()

        print("""
HMS (Home Server Management System)
Version 0.1.0

USAGE:
  hms [OPTIONS] [STACKS] <ACTION> [ARGS]
  hms [OPTIONS] <COMMAND> [SUBCOMMAND] [ARGS]

STACK ACTIONS:""")

        for action in sorted(stack_plugins.keys()):
            print(f"  {action:<12}    (applies to any stack)")

        print("""
GLOBAL COMMANDS:""")

        for command in sorted(global_plugins.keys()):
            subcommands = global_plugins[command]
            subcommand_list = ', '.join(sorted(subcommands.keys()))
            print(f"  {command:<12}    [{subcommand_list}]")

        print(f"""
AVAILABLE STACKS:
  {', '.join(available_stacks) if available_stacks else 'None found'}

OPTIONS:
  --verbose, -v   Verbose output
  --dry-run       Simulate without making changes
  -h, --help      Show this help

EXAMPLES:
  hms platform up                     # Deploy platform
  hms platform,media up               # Deploy multiple stacks
  hms up                              # Deploy all stacks
  hms down --force                    # Stop all stacks
  hms platform prep                   # Run pre-deploy manually
  hms backup create                   # Create backup
  hms show stacks                     # List available stacks
""")

