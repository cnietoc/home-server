"""
HMS Daemon - Servicio que ejecuta jobs periódicos del scheduler.
Diseñado para ejecutarse en el contenedor manteniendo jobs activos.
"""

import logging
import signal
import sys
from pathlib import Path

from hms.lib.logging_config import setup_logging
from hms.lib.paths import get_logs_root
from hms.daemon.scheduler import start_scheduler, stop_scheduler, get_jobs_status, reload_scheduler

logger = logging.getLogger(__name__)


class HMSDaemon:
    """Daemon principal de HMS."""

    def __init__(self):
        """Inicializar daemon."""
        self.running = False

    def setup_signals(self):
        """Configurar manejadores de señales."""
        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGHUP, self._handle_hup)

    def _handle_signal(self, signum, frame):
        """Manejar señal de terminación."""
        logger.info(f"📬 Señal recibida: {signum}")
        self.stop()
        sys.exit(0)

    def _handle_hup(self, signum, frame):
        """Reload de jobs via SIGHUP."""
        logger.info("📬 Señal SIGHUP recibida: recargando jobs...")
        try:
            reload_scheduler()
            logger.info("✅ Jobs recargados")
        except Exception as e:
            logger.error(f"❌ Error recargando jobs: {e}", exc_info=True)

    def start(self):
        """Iniciar daemon con scheduler."""
        self.running = True

        logger.info("🚀 Iniciando HMS Daemon...")
        logger.info(f"📍 PID: {Path('/proc/self').resolve().name if Path('/proc/self').exists() else 'N/A'}")

        try:
            # Mostrar jobs configurados
            logger.info("📋 Jobs configurados:")
            jobs = get_jobs_status()
            for job in jobs:
                logger.info(f"   ✓ {job['name']}")
                logger.info(f"     ID: {job['id']}")
                logger.info(f"     Trigger: {job['trigger']}")

            # Iniciar scheduler
            logger.info("")
            logger.info("⏱️  Iniciando scheduler...")
            start_scheduler()

            logger.info("✅ HMS Daemon activo y ejecutando")
            logger.info("")
            logger.info("Presiona Ctrl+C para detener o envía SIGTERM")
            logger.info("=" * 60)
            logger.info("")

            # Mantener el proceso vivo
            signal.pause()

        except KeyboardInterrupt:
            logger.info("\n⏹️  Daemon detenido por usuario")
            self.stop()
        except Exception as e:
            logger.error(f"❌ Error en daemon: {e}", exc_info=True)
            self.stop()
            sys.exit(1)

    def stop(self):
        """Detener daemon."""
        if self.running:
            logger.info("🛑 Deteniendo HMS Daemon...")
            stop_scheduler()
            logger.info("✅ HMS Daemon detenido")
            self.running = False


def main():
    """Punto de entrada del daemon."""
    # Configurar logging
    log_dir = get_logs_root()
    setup_logging(
        log_file=log_dir / "hms-daemon.log",
        level=logging.INFO,
        console=True,
    )

    logger.info("=" * 60)
    logger.info("🎯 HMS DAEMON")
    logger.info("=" * 60)

    # Crear y ejecutar daemon
    daemon = HMSDaemon()
    daemon.setup_signals()
    daemon.start()


if __name__ == "__main__":
    main()

