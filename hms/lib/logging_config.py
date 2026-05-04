"""Configuración centralizada de logging para HMS.

Proporciona logging a consola y a archivo con rotación automática.
Usa el módulo estándar logging de Python.
"""

import logging
import logging.handlers
import sys
from pathlib import Path


class ColoredFormatter(logging.Formatter):
    """Formatter con colores ANSI para consola."""

    COLORS = {
        'DEBUG': '\033[36m',      # Cyan
        'INFO': '\033[32m',       # Green
        'WARNING': '\033[33m',    # Yellow
        'ERROR': '\033[31m',      # Red
        'CRITICAL': '\033[35m',   # Magenta
    }
    GRAY = '\033[90m'            # Gris
    RESET = '\033[0m'

    def format(self, record):
        # Hacer una copia del record para no contaminar otros handlers
        record_copy = logging.makeLogRecord(record.__dict__)

        # Colorear el nivel (levelname)
        levelname = record_copy.levelname
        if levelname in self.COLORS:
            record_copy.levelname = f"{self.COLORS[levelname]}{levelname}{self.RESET}"

        # Formatear el mensaje completo
        msg = super().format(record_copy)

        # Colorear el timestamp (primeros caracteres antes del espacio)
        # Formato: "2026-01-19 16:02:56 [INFO] ..."
        if ' [' in msg:
            timestamp, rest = msg.split(' [', 1)
            msg = f"{self.GRAY}{timestamp}{self.RESET} [{rest}"

        return msg


class _TagFilter(logging.Filter):
    """Inyecta un campo 'tag' en cada registro para identificar el proceso."""

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
    """Configura logging centralizado en el root logger.

    Args:
        log_file: Ruta del archivo de log. Si es None, no escribe a archivo.
        level: Nivel de logging.
        console: Si True, loguea en consola con colores.
        rotator: Si True, usa RotatingFileHandler (el daemon rota).
                 Si False, usa WatchedFileHandler (el CLI sólo append, sigue inode).
        tag: Etiqueta de proceso que aparece en cada línea del log ("[daemon]", "[cli]").
    """
    root_logger = logging.getLogger()
    root_logger.setLevel(level)
    root_logger.handlers = []

    fmt = "%(asctime)s [%(levelname)s]%(tag_prefix)s %(message)s"
    date_fmt = "%Y-%m-%d %H:%M:%S"

    # Si hay tag, lo inyectamos en el formato vía filtro
    tag_prefix = f" [{tag}]" if tag else ""

    class _TagFormatter(logging.Formatter):
        def format(self, record: logging.LogRecord) -> str:
            record.tag_prefix = tag_prefix
            return super().format(record)

    class _ColoredTagFormatter(ColoredFormatter):
        def format(self, record: logging.LogRecord) -> str:
            record.tag_prefix = tag_prefix
            return super().format(record)

    if console:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(level)
        console_handler.setFormatter(_ColoredTagFormatter(fmt, datefmt=date_fmt))
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
            # WatchedFileHandler: sólo append, detecta cambio de inode tras rollover
            file_handler = logging.handlers.WatchedFileHandler(
                log_file,
                encoding="utf-8",
            )

        file_handler.setLevel(level)
        file_handler.setFormatter(_TagFormatter(fmt, datefmt=date_fmt))
        root_logger.addHandler(file_handler)

    return root_logger
