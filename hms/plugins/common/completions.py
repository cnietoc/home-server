"""Plugin to manage HMS shell completions."""
from pathlib import Path
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
        return "Manage shell tab completions"

    def get_help(self) -> str:
        return """
hms completions - Manage shell tab completions

USAGE:
  hms completions             Show setup instructions
  hms completions install     Install zsh completion to ~/.zsh/completions/_hms
  hms completions print       Print the zsh completion script to stdout

SETUP (after installing):
  Add to ~/.zshrc if not already present:
    fpath=(~/.zsh/completions $fpath)
    autoload -Uz compinit && compinit

  Then restart your shell or run: exec zsh
"""

    def run(self, args: List[str]) -> int:
        if not args or args[0] in ['-h', '--help']:
            print(self.get_help())
            return 0

        subcommand = args[0]

        if subcommand == "install":
            return self._install_zsh()
        elif subcommand == "print":
            print(_ZSH_SCRIPT)
            return 0
        else:
            print(f"Unknown subcommand: {subcommand}")
            print(self.get_help())
            return 1

    @staticmethod
    def _in_docker() -> bool:
        return Path("/.dockerenv").exists()

    def _install_zsh(self) -> int:
        if self._in_docker():
            print("⚠️  hms is running inside Docker — cannot install to the host filesystem.")
            print()
            print("Install manually on the host:")
            print()
            print("  mkdir -p ~/.zsh/completions")
            print("  hms completions print > ~/.zsh/completions/_hms")
            print()
            print("Add to ~/.zshrc if not already present:")
            print()
            print("  fpath=(~/.zsh/completions $fpath)")
            print("  autoload -Uz compinit && compinit")
            print()
            print("Then restart your shell or run: exec zsh")
            return 0

        target_dir = Path.home() / ".zsh" / "completions"
        target_dir.mkdir(parents=True, exist_ok=True)
        completion_file = target_dir / "_hms"
        completion_file.write_text(_ZSH_SCRIPT)

        print(f"✅ Installed zsh completion to {completion_file}")
        print()
        print("Add to ~/.zshrc if not already present:")
        print()
        print("  fpath=(~/.zsh/completions $fpath)")
        print("  autoload -Uz compinit && compinit")
        print()
        print("Then restart your shell or run: exec zsh")
        return 0
