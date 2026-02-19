"""
HMS CLI Dispatcher
Dynamically discovers and loads plugins based on command-line arguments.
"""

import importlib.util
import logging
from pathlib import Path
from typing import List, Optional, Tuple

from hms.core.plugin import BasePlugin, StackPlugin
from hms.lib.plugin_loader import get_plugin_loader
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


class CLIDispatcher:
    """
    Intelligent CLI dispatcher that:
    1. Discovers available plugins dynamically
    2. Parses command-line arguments
    3. Routes to appropriate plugin
    4. Handles both stack and global commands
    """

    def __init__(self):
        """
        Initialize dispatcher.
        """
        self.hms_root = Path(__file__).parent.parent
        self.verbose = False
        self.dry_run = False
        self._stack_manager = stack_metadata
        self.plugin_loader = get_plugin_loader()
        self._stack_manager.list_stacks()

    def discover_stacks(self) -> List[str]:
        """
        Discover available stacks by scanning docker/ directory.

        Returns:
            List of stack names
        """
        return self._stack_manager.list_stacks()

    def discover_stack_plugins(self) -> dict:
        """Discover stack action plugins."""
        return self.plugin_loader.discover_stacks()

    def discover_global_plugins(self) -> dict:
        """Discover global command plugins."""
        return self.plugin_loader.discover_globals()

    def load_plugin(self, plugin_path: str) -> Optional[BasePlugin]:
        """Load a plugin from path."""
        return self.plugin_loader.load(plugin_path)

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

    def is_stack_action(self, arg: str) -> bool:
        """
        Determine if argument is a stack name/list or an action.

        Args:
            arg: Argument to check
            available_stacks: List of known stacks

        Returns:
            True if it's a stack name/list, False otherwise
        """
        available_stacks = self.discover_stacks()
        # Check if it's a single stack
        if arg in available_stacks:
            return True

        # Check if it's comma-separated stacks
        if "," in arg:
            parts = [p.strip() for p in arg.split(",")]
            if all(p in available_stacks for p in parts):
                return True

        return False

    def _sort_with_order(self, names: List[str], order: Optional[List[str]]) -> List[str]:
        """Sort names respecting an optional explicit order."""
        if not order:
            return sorted(names)
        return sorted(names, key=lambda x: (0, order.index(x)) if x in order else (1, x))

    def _load_order(self, module_path: Path, module_name: str) -> Optional[List[str]]:
        """Load COMMAND_ORDER from a module if present."""
        try:
            if not module_path.exists():
                return None
            spec = importlib.util.spec_from_file_location(module_name, module_path)
            if spec is None or spec.loader is None:
                return None
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return getattr(module, 'COMMAND_ORDER', None)
        except Exception as e:
            if self.verbose:
                logger.debug(f"Could not load order from {module_path}: {e}")
            return None

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
            stack_plugins = self.discover_stack_plugins()
            global_plugins = self.discover_global_plugins()
            global_order = self._get_global_command_order()

            # Determine if it's a stack command or global command
            first_arg = args[0]

            # Check if first arg is a stack or stack list
            if self.is_stack_action(first_arg):
                return self._handle_stack_command(args, stack_plugins)

            # Check if it's a known stack action (without stack specified = all stacks)
            elif first_arg in stack_plugins:
                return self._handle_stack_command(args, stack_plugins)

            # Otherwise, treat as global command
            else:
                return self._handle_global_command(args, global_plugins, global_order)

        except KeyboardInterrupt:
            logger.info("⚠️  Interrupted by user")
            return 130
        except Exception as e:
            if self.verbose:
                import traceback
                traceback.print_exc()
            logger.error(f"Error: {e}")
            return 1

    def _handle_stack_command(self, args: List[str], stack_plugins: dict) -> int:
        """Handle stack-specific command."""
        # Parse: [stacks] <action> [args]
        stack_names = []
        action = None
        plugin_args = []

        first_arg = args[0]

        if self.is_stack_action(first_arg):
            # First arg is stack(s)
            stack_names = [s.strip() for s in first_arg.split(",")]
            if len(args) > 1:
                action = args[1]
                plugin_args = args[2:]
            else:
                logger.error("No action specified")
                return 1
        else:
            # First arg is action (apply to all enabled stacks)
            stack_names = []  # Empty = all enabled
            action = args[0]
            plugin_args = args[1:]

        # Validate action exists
        if action not in stack_plugins:
            ordered_actions = self._sort_with_order(list(stack_plugins.keys()), self._get_stack_action_order())
            logger.error(f"Unknown action: {action}")
            logger.info(f"Available actions: {', '.join(ordered_actions)}")
            return 1

        # Load plugin
        plugin = self.load_plugin(stack_plugins[action])
        if not plugin:
            logger.error(f"Failed to load plugin for action: {action}")
            return 1

        # Execute plugin for each stack
        exit_code = 0
        if isinstance(plugin, StackPlugin):
            if not stack_names:
                # Run for all enabled stacks
                exit_code = plugin.run_all_stacks(plugin_args)
            else:
                exit_code = plugin.run_stacks(stack_names if stack_names else "all", plugin_args)

        return exit_code

    def _handle_global_command(self, args: List[str], global_plugins: dict, global_order: Optional[List[str]]) -> int:
        """Handle global command."""
        # Parse: <command> [subcommand] [args]
        command = args[0]

        if command not in global_plugins:
            ordered_commands = self._sort_with_order(list(global_plugins.keys()), global_order)
            logger.error(f"Unknown command: {command}")
            logger.info(f"Available commands: {', '.join(ordered_commands)}")
            return 1

        plugin_entry = global_plugins[command]

        # Commands implemented as a single file (no subcommands)
        if isinstance(plugin_entry, str):
            plugin = self.load_plugin(plugin_entry)
            if not plugin:
                logger.error(f"Failed to load plugin for command: {command}")
                return 1
            plugin_args = args[1:]
            if self.verbose:
                logger.debug(f"Executing {command}...")
            return plugin.run(plugin_args)

        subcommands = plugin_entry

        if len(args) > 1:
            subcommand = args[1]
            plugin_args = args[2:]
        else:
            # No subcommand = show detailed help for this command
            self._print_command_help(command, subcommands)
            return 0

        if subcommand not in subcommands:
            logger.error(f"Unknown subcommand: {command} {subcommand}")
            self._print_command_help(command, subcommands)
            return 1

        # Load plugin
        plugin = self.load_plugin(subcommands[subcommand])
        if not plugin:
            logger.error(f"Failed to load plugin for: {command} {subcommand}")
            return 1

        if self.verbose:
            logger.debug(f"Executing {command} {subcommand}...")

        return plugin.run(plugin_args)

    def _print_command_help(self, command: str, subcommands: dict) -> None:
        """Print detailed help for a specific command with its subcommands."""
        # Single-file command without subcommands
        if isinstance(subcommands, str):
            plugin = self.load_plugin(subcommands)
            description = plugin.get_description() if plugin else "(no description available)"
            print(f"""
{'=' * 60}
HMS Command: {command}
{'=' * 60}

Description:
  {description}

USAGE:
  hms {command} [args]

EXAMPLES:
  hms {command}
  hms {command} --help
""")
            return

        subcommand_order = self._get_subcommand_order(command)

        plugin_info = {}
        for subcommand_name, plugin_path in subcommands.items():
            plugin = self.load_plugin(plugin_path)
            if plugin:
                plugin_info[subcommand_name] = plugin.get_description()
            else:
                plugin_info[subcommand_name] = "(no description available)"

        ordered_names = self._sort_with_order(list(plugin_info.keys()), subcommand_order)

        print(f"""
{'=' * 60}
HMS Command: {command}
{'=' * 60}

Available subcommands:
""")

        for subcommand_name in ordered_names:
            description = plugin_info[subcommand_name]
            print(f"  {subcommand_name:<15} {description}")

        print(f"""
USAGE:
  hms {command} <subcommand> [args]

EXAMPLES:
  hms {command} {ordered_names[0] if ordered_names else 'subcommand'}
  hms {command} {ordered_names[0] if ordered_names else 'subcommand'} --help
""")

    def _get_subcommand_order(self, command: str) -> Optional[List[str]]:
        """Load the COMMAND_ORDER from a command category's __init__.py."""
        category_dir = self.hms_root / "plugins" / "global" / command
        return self._load_order(category_dir / "__init__.py", f"hms.plugins.global.{command}")

    def _get_stack_action_order(self) -> Optional[List[str]]:
        """Load COMMAND_ORDER from plugins/stacks/__init__.py for stack actions."""
        return self._load_order(self.hms_root / "plugins" / "stacks" / "__init__.py", "hms.plugins.stacks")

    def _get_global_command_order(self) -> Optional[List[str]]:
        """Load COMMAND_ORDER from plugins/global/__init__.py for global commands."""
        return self._load_order(self.hms_root / "plugins" / "global" / "__init__.py", "hms.plugins.global")

    def print_help(self) -> None:
        """Print general help text."""
        available_stacks = self.discover_stacks()
        stack_plugins = self.discover_stack_plugins()
        global_plugins = self.discover_global_plugins()
        stack_order = self._get_stack_action_order()
        global_order = self._get_global_command_order()

        print("""
HMS (Home Server Management System)
Version 0.1.0

USAGE:
  hms [OPTIONS] [STACKS] <ACTION> [ARGS]
  hms [OPTIONS] <COMMAND> [SUBCOMMAND] [ARGS]
  hms stack <stack_name> <command> [OPTIONS]           # NEW: TOML-based stacks

STACK ACTIONS (legacy):
""")

        for action in self._sort_with_order(list(stack_plugins.keys()), stack_order):
            description = "(no description available)"
            plugin = self.load_plugin(stack_plugins[action])
            if plugin:
                description = plugin.get_description()
            print(f"  {action:<12}    {description}")

        print("""
GLOBAL COMMANDS:
""")

        for command in self._sort_with_order(list(global_plugins.keys()), global_order):
            subcommands = global_plugins[command]
            if isinstance(subcommands, str):
                plugin = self.load_plugin(subcommands)
                description = plugin.get_description() if plugin else "(no description available)"
                print(f"  {command:<12}    {description}")
                continue

            print(f"  {command}:")
            subcommand_order = self._get_subcommand_order(command)
            for subcommand_name in self._sort_with_order(list(subcommands.keys()), subcommand_order):
                plugin = self.load_plugin(subcommands[subcommand_name])
                description = plugin.get_description() if plugin else "(no description available)"
                print(f"    {subcommand_name:<12}  {description}")

        print(f"""
NEW COMMAND - TOML-BASED STACKS:
  stack validate                Valida la configuración TOML
  stack <name> up               Levanta un stack
  stack <name> down             Derriba un stack
  stack <name> restart          Reinicia un stack o servicios
  stack <name> logs [-f]        Ver logs (con -f para seguir)
  stack <name> ps               Estado del stack
  stack <name> config           Configuración resolvida
  stack <name> env              Variables de entorno inyectadas

OPTIONS:
  --verbose, -v   Verbose output
  --dry-run       Simulate without making changes
  -h, --help      Show this help

EXAMPLES:
""")

        # Generar ejemplos dinámicamente
        first_stack = available_stacks[0] if available_stacks else 'STACK'
        ordered_actions = self._sort_with_order(list(stack_plugins.keys()), stack_order)
        first_action = ordered_actions[0] if ordered_actions else 'ACTION'

        sample_global = "hms COMMAND subcommand"
        if global_plugins:
            ordered_commands = self._sort_with_order(list(global_plugins.keys()), global_order)
            first_command = ordered_commands[0] if ordered_commands else 'COMMAND'
            first_entry = global_plugins[first_command]
            if isinstance(first_entry, str):
                sample_global = f"hms {first_command}"
            else:
                subcommand_order = self._get_subcommand_order(first_command)
                ordered_subs = self._sort_with_order(list(first_entry.keys()), subcommand_order)
                sample_subcommand = ordered_subs[0] if ordered_subs else 'subcommand'
                sample_global = f"hms {first_command} {sample_subcommand}"

        if available_stacks:
            print(f"  hms {first_stack} {first_action}                     # {first_action.capitalize()} {first_stack}")
            if len(available_stacks) > 1:
                second_stack = available_stacks[1]
                print(f"  hms {first_stack},{second_stack} {first_action}               # {first_action.capitalize()} multiple stacks")
            print(f"  hms {first_action}                              # {first_action.capitalize()} all stacks")
        else:
            print("  (no stacks available)")

        print(f"""
  {sample_global}                   # Run a global command
  hms stack helloworld up            # NEW: Levanta stack desde TOML
  hms stack media env --verbose      # NEW: Variables de entorno
  hms --help                          # Show this help
  hms {first_stack} {first_action} --verbose          # Verbose output
""")
