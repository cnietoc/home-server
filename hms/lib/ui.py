"""
hms.lib.ui — user-visible output in the CLI.

Separated from the logger so that user feedback does not depend on log_level.
Use in plugins for status messages, results, and errors visible in the terminal.
Use logger.* for diagnostics and records written to hms.log.

In daemon context (HMS_DAEMON=1) redirects to logger to avoid polluting docker logs.
"""

import logging
import os
import sys

_logger = logging.getLogger("hms.ui")


def _daemon() -> bool:
    return bool(os.environ.get("HMS_DAEMON"))


def _log_lines(log_fn, msg: str) -> None:
    for line in str(msg).split("\n"):
        if line:
            log_fn(line)


def info(msg: str) -> None:
    if _daemon():
        _log_lines(_logger.info, msg)
    else:
        print(msg)


def ok(msg: str) -> None:
    if _daemon():
        _log_lines(_logger.info, msg)
    else:
        print(f"✅ {msg}")


def warn(msg: str) -> None:
    if _daemon():
        _log_lines(_logger.warning, msg)
    else:
        print(f"⚠️  {msg}", file=sys.stderr)


def err(msg: str) -> None:
    if _daemon():
        _log_lines(_logger.error, msg)
    else:
        print(f"❌ {msg}", file=sys.stderr)
