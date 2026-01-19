"""
HMS Entry Point
Run as: python -m hms [args]
"""

import sys

from hms.core.cli import CLIDispatcher


def main():
    """Main entry point."""
    dispatcher = CLIDispatcher()
    exit_code = dispatcher.dispatch(sys.argv[1:])
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
