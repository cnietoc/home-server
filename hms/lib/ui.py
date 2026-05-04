"""
hms.lib.ui — output visible al usuario en el CLI.

Separado del logger para que el feedback al usuario no dependa del log_level.
Usar en plugins para mensajes de estado, resultados y errores visibles en terminal.
Usar logger.* para diagnósticos y registros en hms.log.

En contexto de daemon (HMS_DAEMON=1) redirige a logger para no contaminar docker logs.
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
