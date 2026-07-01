"""
Plugin: self-update
Updates the repository and restarts HMS
"""

from hms.core.plugin import GlobalPlugin


class SelfUpdatePlugin(GlobalPlugin):
    """Self-update command - Pulls from repo and restarts HMS."""

    def get_name(self) -> str:
        return "self-update"

    def get_description(self) -> str:
        return "Update HMS from repository and restart"

    def get_help(self) -> str:
        return """
self-update - Update HMS from the repository

USAGE:
  hms self-update

DESCRIPTION:
  Pulls the latest changes from the repository and restarts HMS services.

  This command will:
    1. Perform git pull to fetch latest changes
    2. Detect relevant code changes
    3. Stop HMS services gracefully
    4. Start HMS services (rebuilding Docker image if necessary)
    5. Display summary of applied changes

NOTE:
  This command delegates to commands/self-update script for execution.
"""

    def run(self, args: list) -> int:
        raise NotImplementedError("This command should be handled by the wrapper in hms/bin/hms")
