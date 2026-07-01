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

_BASH_SCRIPT = """\
# HMS bash completion
# Source this file or place it in /etc/bash_completion.d/hms

_hms() {
    local completions
    completions=$(hms --complete "$((COMP_CWORD + 1))" "${COMP_WORDS[@]}" 2>/dev/null)
    COMPREPLY=($(compgen -W "$completions" -- "${COMP_WORDS[$COMP_CWORD]}"))
}

complete -F _hms hms
"""


class CompletionsPlugin(GlobalPlugin):
    def get_name(self) -> str:
        return "completions"

    def get_description(self) -> str:
        return "Print the shell tab completion script"

    def get_help(self) -> str:
        return """
hms completions - Print the shell tab completion script

USAGE:
  hms completions print zsh    Print the zsh completion script to stdout
  hms completions print bash   Print the bash completion script to stdout

INSTALL (zsh):
  mkdir -p ~/.zsh/completions
  hms completions print zsh > ~/.zsh/completions/_hms
  # Add to ~/.zshrc: fpath=(~/.zsh/completions $fpath) && autoload -Uz compinit && compinit

INSTALL (bash):
  hms completions print bash > ~/.bash_completion.d/hms
  # Add to ~/.bashrc: source ~/.bash_completion.d/hms

NOTE:
  install.sh sets this up automatically based on your current shell.
"""

    def run(self, args: List[str]) -> int:
        if not args or args[0] in ["-h", "--help"]:
            print(self.get_help())
            return 0

        if args[0] == "print":
            shell = args[1] if len(args) > 1 else self._detect_shell()
            if shell == "zsh":
                print(_ZSH_SCRIPT, end="")
                return 0
            elif shell == "bash":
                print(_BASH_SCRIPT, end="")
                return 0
            else:
                print(f"Unsupported shell: {shell}. Use 'zsh' or 'bash'.")
                return 1

        print(f"Unknown subcommand: {args[0]}")
        print(self.get_help())
        return 1

    @staticmethod
    def _detect_shell() -> str:
        import os

        shell = os.environ.get("SHELL", "")
        if "zsh" in shell:
            return "zsh"
        return "bash"
