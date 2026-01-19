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


def setup_logging(
    log_file: Path | None = None,
    level: int = logging.INFO,
    console: bool = True,
) -> logging.Logger:
    """Configura logging centralizado en el root logger.

    Captura logs de todos los módulos (hms.*, etc.) tanto en consola
    como en archivo. Consola con colores, archivo sin colores.

    Args:
        log_file: Ruta del archivo de log (con rotación automática).
                 Si es None, no se escribe a archivo.
        level: Nivel de logging (DEBUG, INFO, WARNING, ERROR, CRITICAL).
        console: Si True, también loguea en consola con colores.

    Ejemplo:
        setup_logging(
            log_file=Path("/app/data/logs/hms.log"),
            level=logging.INFO,
        )
    """
    # Configurar root logger (captura todos los logs)
    root_logger = logging.getLogger()
    root_logger.setLevel(level)

    # Limpiar handlers existentes si se llama múltiples veces
    root_logger.handlers = []

    # Formato base (sin colores para archivo)
    fmt = "%(asctime)s [%(levelname)s] %(message)s"
    date_fmt = "%Y-%m-%d %H:%M:%S"

    # Handler de consola (con colores)
    if console:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(level)
        console_formatter = ColoredFormatter(fmt, datefmt=date_fmt)
        console_handler.setFormatter(console_formatter)
        root_logger.addHandler(console_handler)

    # Handler de archivo (sin colores)
    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)

        # RotatingFileHandler: máx 10MB por archivo, máx 5 backups
        file_handler = logging.handlers.RotatingFileHandler(
            log_file,
            maxBytes=10 * 1024 * 1024,  # 10MB
            backupCount=5,
            encoding='utf-8'
        )
        file_handler.setLevel(level)
        # Formatter sin colores para archivo
        file_formatter = logging.Formatter(fmt, datefmt=date_fmt)
        file_handler.setFormatter(file_formatter)
        root_logger.addHandler(file_handler)

    return root_logger

