"""
Plugin: install
Installs HMS and creates the symlink in ~/.local/bin/hms
"""

from hms.core.plugin import GlobalPlugin


class InstallPlugin(GlobalPlugin):
    """Install command - Sets up HMS symlink and configuration."""

    def get_name(self) -> str:
        return "install"

    def get_description(self) -> str:
        return "Install HMS and create symlink in ~/.local/bin/hms"

    def get_help(self) -> str:
        return """
install - Install HMS with symlink and configuration

USAGE:
  hms install [--force]

DESCRIPTION:
  Creates a symlink in ~/.local/bin/hms pointing to the HMS wrapper.
  Sets up config.toml with PUID, PGID, timezone, and other settings.
  
  This command is typically run once during initial setup, but can be
  run again with --force to reinstall or update the symlink.

OPTIONS:
  --force    Force reinstall, overwriting existing symlink

EXAMPLES:
  hms install              # Install HMS
  hms install --force      # Force reinstall

NOTE:
  This command delegates to commands/install script for execution.
"""

    def run(self, args: list) -> int:
        """Execute install command."""
        # This is handled by the wrapper in hms/bin/hms
        # which delegates to commands/install
        raise NotImplementedError(
            "This command should be handled by the wrapper in hms/bin/hms"
        )
