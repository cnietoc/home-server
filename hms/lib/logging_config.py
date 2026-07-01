"""Centralised logging configuration for HMS.

Provides logging to console and to file with automatic rotation.
Uses Python's standard logging module.
"""

import logging
import logging.handlers
import sys
from pathlib import Path


class _SimpleColoredFormatter(logging.Formatter):
    """Simple console formatter: message only, with colour by level (WARNING+)."""

    LEVEL_COLOR = {
        "DEBUG": "\033[36m",  # Cyan
        "WARNING": "\033[33m",  # Yellow
        "ERROR": "\033[31m",  # Red
        "CRITICAL": "\033[35m",  # Magenta
    }
    RESET = "\033[0m"

    def format(self, record: logging.LogRecord) -> str:
        msg = record.getMessage()
        color = self.LEVEL_COLOR.get(record.levelname)
        if color:
            return f"{color}{record.levelname}: {msg}{self.RESET}"
        return msg  # INFO: no prefix, no color


class ColoredFormatter(logging.Formatter):
    """ANSI-coloured formatter for console — kept for compatibility (not used in CLI)."""

    COLORS = {
        "DEBUG": "\033[36m",
        "INFO": "\033[32m",
        "WARNING": "\033[33m",
        "ERROR": "\033[31m",
        "CRITICAL": "\033[35m",
    }
    GRAY = "\033[90m"
    RESET = "\033[0m"

    def format(self, record):
        record_copy = logging.makeLogRecord(record.__dict__)
        levelname = record_copy.levelname
        if levelname in self.COLORS:
            record_copy.levelname = f"{self.COLORS[levelname]}{levelname}{self.RESET}"
        msg = super().format(record_copy)
        if " [" in msg:
            timestamp, rest = msg.split(" [", 1)
            msg = f"{self.GRAY}{timestamp}{self.RESET} [{rest}"
        return msg


class _TagFilter(logging.Filter):
    """Injects a 'tag' field into each log record to identify the process."""

    def __init__(self, tag: str):
        super().__init__()
        self.tag = tag

    def filter(self, record: logging.LogRecord) -> bool:
        record.tag = self.tag
        return True


def setup_logging(
    log_file: Path | None = None,
    level: int = logging.INFO,
    console: bool = True,
    rotator: bool = False,
    tag: str = "",
) -> logging.Logger:
    """Configures centralised logging on the root logger.

    Args:
        log_file: Path to the log file. If None, does not write to file.
        level: Logging level.
        console: If True, logs to console with colours.
        rotator: If True, uses RotatingFileHandler (daemon rotates).
                 If False, uses WatchedFileHandler (CLI append-only, follows inode).
        tag: Process label that appears on each log line ("[daemon]", "[cli]").
    """
    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    root_logger.handlers = []

    fmt = "%(asctime)s [%(levelname)-7s]%(tag_prefix)s %(message)s"
    date_fmt = "%Y-%m-%d %H:%M:%S"

    # Tag right-aligned, width of the longest value ("daemon" = 6), with pipe separator
    _TAG_WIDTH = 6
    tag_prefix = f" {tag.rjust(_TAG_WIDTH)} |" if tag else ""

    class _TagFormatter(logging.Formatter):
        def format(self, record: logging.LogRecord) -> str:
            record.tag_prefix = tag_prefix
            return super().format(record)

    class _ColoredTagFormatter(ColoredFormatter):
        def format(self, record: logging.LogRecord) -> str:
            record.tag_prefix = tag_prefix
            return super().format(record)

    if console:
        console_handler = logging.StreamHandler(sys.stderr)
        # INFO/DEBUG go to file only; console shows WARNING+ with simple format.
        # Exception: in DEBUG mode (via -vv) the level is lowered for interactive debugging.
        console_level = level if level <= logging.DEBUG else logging.WARNING
        console_handler.setLevel(console_level)
        console_handler.setFormatter(_SimpleColoredFormatter())
        root_logger.addHandler(console_handler)

    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)

        if rotator:
            file_handler = logging.handlers.RotatingFileHandler(
                log_file,
                maxBytes=10 * 1024 * 1024,
                backupCount=5,
                encoding="utf-8",
            )
        else:
            # WatchedFileHandler: append-only, detects inode change after rollover
            file_handler = logging.handlers.WatchedFileHandler(
                log_file,
                encoding="utf-8",
            )

        file_handler.setLevel(level)
        file_handler.setFormatter(_TagFormatter(fmt, datefmt=date_fmt))
        root_logger.addHandler(file_handler)

    return root_logger
