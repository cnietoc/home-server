"""
HMS Entry Point
Run as: python -m hms [args]
"""

import logging
import sys

from hms.cli.cli import CLIDispatcher
from hms.lib.config import config_manager
from hms.lib.logging_config import setup_logging
from hms.lib.paths import get_logs_root


def main():
    """Main entry point."""
    # Fast path for tab completions — skip logging and config setup
    if len(sys.argv) > 1 and sys.argv[1] == '--complete':
        from hms.cli.complete import handle_complete
        handle_complete(sys.argv[2:])
        sys.exit(0)

    # Establecer variables de entorno
    log_level = config_manager.get_config_value("global.log_level")

    # Configurar logging global (una sola vez)
    log_dir = get_logs_root()
    setup_logging(
        log_file=log_dir / "hms-cli.log",
        level=logging.getLevelName(log_level.upper()),
    )
    config_manager.load_env_config()

    dispatcher = CLIDispatcher()
    exit_code = dispatcher.dispatch(sys.argv[1:])
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
