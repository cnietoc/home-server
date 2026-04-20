"""Plugin to manage HMS shell completions."""
from typing import List

from hms.core.plugin import GlobalPlugin

_ZSH_SCRIPT = """\
#compdef hms

_hms() {
    local completions
    completions=$(hms --complete "$CURRENT" "${words[@]}" 2>/dev/null)

    if [[ -n "$completions" ]]; then
        local -a items
        items=(${(f)completions})
        _describe 'hms' items
    fi
}

_hms
"""


class CompletionsPlugin(GlobalPlugin):
    def get_name(self) -> str:
        return "completions"

    def get_description(self) -> str:
        return "Print the zsh tab completion script"

    def get_help(self) -> str:
        return """
hms completions - Print the zsh tab completion script

USAGE:
  hms completions print       Print the zsh completion script to stdout

INSTALL:
  mkdir -p ~/.zsh/completions
  hms completions print > ~/.zsh/completions/_hms

  Add to ~/.zshrc if not already present:
    fpath=(~/.zsh/completions $fpath)
    autoload -Uz compinit && compinit

  Then restart your shell or run: exec zsh

NOTE:
  install.sh sets this up automatically.
"""

    def run(self, args: List[str]) -> int:
        if not args or args[0] in ['-h', '--help']:
            print(self.get_help())
            return 0

        if args[0] == "print":
            print(_ZSH_SCRIPT, end="")
            return 0

        print(f"Unknown subcommand: {args[0]}")
        print(self.get_help())
        return 1
