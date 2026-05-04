"""
HMS Daemon - Service that runs periodic scheduler jobs.
The scheduler integrates with FastAPI via lifespan events.
"""

import logging
import logging.handlers

import uvicorn

from hms.lib.config import config_manager
from hms.lib.logging_config import setup_logging
from hms.lib.paths import get_logs_root

logger = logging.getLogger(__name__)


def main():
    """Daemon entry point."""
    import os
    os.environ["HMS_DAEMON"] = "1"  # ui.* redirects to logger instead of print

    # Load configuration and set environment variables
    log_level = config_manager.get_config_value("global.log_level")

    # Set up centralised logging
    log_dir = get_logs_root()
    setup_logging(
        log_file=log_dir / "hms.log",
        level=logging.getLevelName(log_level.upper()),
        console=False,
        rotator=True,
        tag="daemon",
    )
    config_manager.load_env_config()

    # uvicorn.error → root logger (hms.log), uvicorn.access → separate access.log
    for name in ("uvicorn", "uvicorn.error"):
        uv_logger = logging.getLogger(name)
        uv_logger.handlers = []
        uv_logger.propagate = True
        uv_logger.setLevel(logging.INFO)

    _access_handler = logging.handlers.RotatingFileHandler(
        log_dir / "access.log", maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8"
    )
    _access_handler.setFormatter(logging.Formatter("%(asctime)s %(message)s", "%Y-%m-%d %H:%M:%S"))
    uv_access = logging.getLogger("uvicorn.access")
    uv_access.handlers = [_access_handler]
    uv_access.propagate = False
    uv_access.setLevel(logging.INFO)

    # httpx/httpcore: outgoing requests — INFO is too verbose, WARNING is sufficient
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)

    logger.info("=" * 60)
    logger.info("🎯 HMS DAEMON")
    logger.info("=" * 60)
    logger.info("🌐 API available at 0.0.0.0:8080")
    logger.info("")

    # Run uvicorn
    # log_level="warning": uvicorn only shows warnings/errors
    # Scheduler/FastAPI logs go to the root logger (console + file)
    uvicorn.run(
        "hms.daemon.api:app",
        host="0.0.0.0",
        port=8080,
        log_level="info",
        access_log=True,
        log_config=None,  # Use the already-configured handlers/formatters
    )


if __name__ == "__main__":
    main()
