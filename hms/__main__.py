"""
HMS Entry Point
Run as: python -m hms [args]
"""

import sys
import os
from pathlib import Path

# Set up project root
project_root = os.environ.get('PROJECT_ROOT')
if not project_root:
    # Default to parent directory of hms module
    project_root = str(Path(__file__).parent.parent)

from hms.core.cli import CLIDispatcher


def main():
    """Main entry point."""
    dispatcher = CLIDispatcher(project_root=project_root)
    exit_code = dispatcher.dispatch(sys.argv[1:])
    sys.exit(exit_code)


if __name__ == "__main__":
    main()

