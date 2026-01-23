"""
HMS Daemon - Servicio que ejecuta jobs periódicos del scheduler.
El scheduler se integra con FastAPI via lifespan events.
"""

import logging

import uvicorn

from hms.lib.config import config_manager
from hms.lib.logging_config import setup_logging
from hms.lib.paths import get_logs_root

logger = logging.getLogger(__name__)


def main():
    """Punto de entrada del daemon."""
    # Cargar configuración y establecer variables de entorno
    log_level = config_manager.get_config_value("global.log_level")

    # Configurar logging centralizado
    log_dir = get_logs_root()
    setup_logging(
        log_file=log_dir / "hms-daemon.log",
        level=logging.getLevelName(log_level.upper()),
        console=True,
    )
    config_manager.load_env_config()

    # Hacer que los loggers de uvicorn usen los handlers/formatos globales
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        uv_logger = logging.getLogger(name)
        uv_logger.handlers = []  # limpia handlers propios
        uv_logger.propagate = True  # reenvía al root con formato unificado
        uv_logger.setLevel(logging.INFO)

    logger.info("=" * 60)
    logger.info("🎯 HMS DAEMON")
    logger.info("=" * 60)
    logger.info("🌐 API disponible en 0.0.0.0:8080")
    logger.info("")

    # Ejecutar uvicorn
    # log_level="warning": uvicorn solo muestra warnings/errors
    # Los logs del scheduler/FastAPI van al root logger (consola + archivo)
    uvicorn.run(
        "hms.daemon.api:app",
        host="0.0.0.0",
        port=8080,
        log_level="info",
        access_log=True,
        log_config=None,  # Usa los handlers/formatos ya configurados
    )


if __name__ == "__main__":
    main()
