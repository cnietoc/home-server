"""Fast completion handler for HMS CLI."""
from typing import List


def get_completions(words: List[str], current_index: int) -> List[str]:
    """
    Return completions for the word at current_index.

    words: full word list (words[0] = "hms")
    current_index: 1-based index matching zsh $CURRENT
    """
    from hms.lib.plugin_loader import get_plugin_loader
    from hms.lib.stacks import stack_metadata

    plugin_loader = get_plugin_loader()

    # Words already confirmed before the current position (excludes "hms")
    typed = words[1:current_index - 1]

    stack_actions = plugin_loader.discover_stacks()
    global_plugins = plugin_loader.discover_globals()

    if not typed:
        # Position 1: actions + global commands
        return list(stack_actions.keys()) + list(global_plugins.keys())

    first = typed[0]

    if first in stack_actions:
        # Position 2: stack names (or nothing if already given)
        if len(typed) == 1:
            return stack_metadata.list_stacks()
        return []

    if first in global_plugins:
        entry = global_plugins[first]
        if isinstance(entry, dict) and len(typed) == 1:
            return list(entry.keys())
        return []

    return []


def handle_complete(args: List[str]) -> None:
    """Handle --complete mode: print one completion per line to stdout."""
    if len(args) < 2:
        return
    try:
        current_index = int(args[0])
        words = args[1:]
        completions = get_completions(words, current_index)
        print("\n".join(completions))
    except Exception:
        pass
