"""
HMS Entry Point
Run as: python -m hms [args]
"""

import logging
import os
import sys
import time

from hms.cli.cli import CLIDispatcher
from hms.lib.config import config_manager
from hms.lib.logging_config import setup_logging
from hms.lib.paths import get_logs_root

_cli_event_logger = logging.getLogger("hms.cli.event")


def main():
    """Main entry point."""
    # Fast path for tab completions — skip logging and config setup
    if len(sys.argv) > 1 and sys.argv[1] == "--complete":
        from hms.cli.complete import handle_complete

        handle_complete(sys.argv[2:])
        sys.exit(0)

    # Consume -v/-vv before parsing the rest of the args
    args = sys.argv[1:]
    if "-vv" in args:
        verbose = 2
        args = [a for a in args if a != "-vv"]
    elif "-v" in args:
        verbose = 1
        args = [a for a in args if a != "-v"]
    else:
        verbose = 0

    # Resolve log level: -vv > -v > HMS_LOG_LEVEL > config.toml
    base_level = config_manager.get_config_value("global.log_level").upper()
    env_level = os.environ.get("HMS_LOG_LEVEL", "").upper()
    if verbose >= 2:
        level_str = "DEBUG"
    elif verbose == 1:
        level_str = "INFO"
    elif env_level in ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"):
        level_str = env_level
    else:
        level_str = base_level

    tag = os.environ.get("HMS_LOG_TAG", "cli")

    log_dir = get_logs_root()
    setup_logging(
        log_file=log_dir / "hms.log",
        level=logging.getLevelName(level_str),
        console=True,
        rotator=False,
        tag=tag,
    )
    config_manager.load_env_config()

    cmd_str = " ".join(args) if args else "(no args)"
    _cli_event_logger.info("▶ CLI start: %s", cmd_str)
    t0 = time.monotonic()
    exit_code = 1
    try:
        dispatcher = CLIDispatcher()
        exit_code = dispatcher.dispatch(args)
        sys.exit(exit_code)
    finally:
        elapsed_ms = (time.monotonic() - t0) * 1000
        _cli_event_logger.info("⏹ CLI end: %s — %.0fms (exit=%d)", cmd_str, elapsed_ms, exit_code)


if __name__ == "__main__":
    main()
