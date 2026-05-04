"""
HMS Daemon - Servicio que ejecuta jobs periódicos del scheduler.
El scheduler se integra con FastAPI via lifespan events.
"""

import logging
import logging.handlers

import uvicorn

from hms.lib.config import config_manager
from hms.lib.logging_config import setup_logging
from hms.lib.paths import get_logs_root

logger = logging.getLogger(__name__)


def main():
    """Punto de entrada del daemon."""
    import os
    os.environ["HMS_DAEMON"] = "1"  # ui.* redirige a logger en vez de print

    # Cargar configuración y establecer variables de entorno
    log_level = config_manager.get_config_value("global.log_level")

    # Configurar logging centralizado
    log_dir = get_logs_root()
    setup_logging(
        log_file=log_dir / "hms.log",
        level=logging.getLevelName(log_level.upper()),
        console=False,
        rotator=True,
        tag="daemon",
    )
    config_manager.load_env_config()

    # uvicorn.error → root logger (hms.log), uvicorn.access → access.log separado
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

    # httpx/httpcore: peticiones salientes — INFO es demasiado verboso, WARNING basta
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)

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
