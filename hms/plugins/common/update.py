"""
Plugin: update
Updates the repository and restarts HMS
"""

from hms.core.plugin import GlobalPlugin


class UpdatePlugin(GlobalPlugin):
    """Update command - Pulls from repo and restarts HMS."""

    def get_name(self) -> str:
        return "update"

    def get_description(self) -> str:
        return "Update HMS from repository and restart"

    def get_help(self) -> str:
        return """
update - Update HMS from the repository

USAGE:
  hms update

DESCRIPTION:
  Pulls the latest changes from the repository and restarts HMS services.
  
  This command will:
    1. Perform git pull to fetch latest changes
    2. Detect relevant code changes
    3. Stop HMS services gracefully
    4. Start HMS services (rebuilding Docker image if necessary)
    5. Display summary of applied changes

EXAMPLES:
  hms update    # Update and restart HMS

NOTE:
  This command delegates to commands/update script for execution.
"""

    def run(self, args: list) -> int:
        """Execute update command."""
        # This is handled by the wrapper in hms/bin/hms
        # which delegates to commands/update
        raise NotImplementedError(
            "This command should be handled by the wrapper in hms/bin/hms"
        )
