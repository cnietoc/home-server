"""
hms.lib.ui — output visible al usuario en el CLI.

Separado del logger para que el feedback al usuario no dependa del log_level.
Usar en plugins para mensajes de estado, resultados y errores visibles en terminal.
Usar logger.* para diagnósticos y registros en hms.log.
"""

import sys


def info(msg: str) -> None:
    print(msg)


def ok(msg: str) -> None:
    print(f"✅ {msg}")


def warn(msg: str) -> None:
    print(f"⚠️  {msg}", file=sys.stderr)


def err(msg: str) -> None:
    print(f"❌ {msg}", file=sys.stderr)
