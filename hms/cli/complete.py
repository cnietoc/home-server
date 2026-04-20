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

    if not typed:
        stacks = stack_metadata.list_stacks()
        stack_actions = list(plugin_loader.discover_stacks().keys())
        global_cmds = list(plugin_loader.discover_globals().keys())
        return stacks + stack_actions + global_cmds

    first = typed[0]
    stacks = stack_metadata.list_stacks()

    is_stack = first in stacks or (
        "," in first and all(s.strip() in stacks for s in first.split(","))
    )

    if is_stack:
        if len(typed) == 1:
            return list(plugin_loader.discover_stacks().keys())
        return []

    if first in plugin_loader.discover_stacks():
        return []

    global_plugins = plugin_loader.discover_globals()
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
