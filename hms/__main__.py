"""
HMS Entry Point
Run as: python -m hms [args]
"""

import logging
import sys

from hms.core.cli import CLIDispatcher
from hms.lib.logging_config import setup_logging
from hms.lib.paths import get_logs_root


def main():
    """Main entry point."""
    # Configurar logging global (una sola vez)
    log_dir = get_logs_root()
    setup_logging(
        log_file=log_dir / "hms.log",
        level=logging.INFO,
    )

    dispatcher = CLIDispatcher()
    exit_code = dispatcher.dispatch(sys.argv[1:])
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
