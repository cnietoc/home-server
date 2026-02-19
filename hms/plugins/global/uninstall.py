"""
Plugin: uninstall
Removes HMS symlink and stops services
"""

from hms.core.plugin import GlobalPlugin


class UninstallPlugin(GlobalPlugin):
    """Uninstall command - Stops HMS and removes symlink."""

    def get_name(self) -> str:
        return "uninstall"

    def get_description(self) -> str:
        return "Uninstall HMS and remove symlink"

    def get_help(self) -> str:
        return """
uninstall - Uninstall HMS and remove symlink

USAGE:
  hms uninstall

DESCRIPTION:
  Stops HMS services and removes the symlink from ~/.local/bin/hms.
  
  This command will:
    1. Stop HMS services gracefully
    2. Remove the symlink from ~/.local/bin/hms
    3. Leave all data and configuration intact
  
  To completely remove HMS, you can then manually delete:
    - The repository directory
    - Configuration files (config.toml, config/ directory)
    - Data directories if needed

EXAMPLES:
  hms uninstall    # Uninstall HMS

NOTE:
  This command delegates to commands/uninstall script for execution.
"""

    def run(self, args: list) -> int:
        """Execute uninstall command."""
        # This is handled by the wrapper in hms/bin/hms
        # which delegates to commands/uninstall
        raise NotImplementedError(
            "This command should be handled by the wrapper in hms/bin/hms"
        )
