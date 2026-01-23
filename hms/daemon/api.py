"""
Mini API REST para el daemon HMS.
Solo expone endpoint /health para healthcheck del contenedor.
Integra el scheduler APScheduler en el ciclo de vida de FastAPI.
"""

import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import JSONResponse

from hms.daemon.scheduler import (
    check_scheduler_running,
    get_jobs_status,
    start_scheduler,
    stop_scheduler,
)

logger = logging.getLogger(__name__)

# Variables globales para tracking
_start_time = time.time()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Gestión del ciclo de vida de la aplicación.
    Inicia el scheduler al arrancar y lo detiene al cerrar.
    """
    # Startup
    logger.info("⏱️  Iniciando scheduler...")
    start_scheduler()

    # Mostrar jobs configurados
    jobs = get_jobs_status()
    logger.info(f"📋 Scheduler iniciado con {len(jobs)} job(s)")
    for job in jobs:
        logger.info(f"   ✓ {job['name']} ({job['id']}) - {job['trigger']}")

    yield

    # Shutdown
    logger.info("🛑 Deteniendo scheduler...")
    stop_scheduler()
    logger.info("✅ Scheduler detenido")


# Crear app FastAPI con lifespan
app = FastAPI(
    title="HMS Daemon API",
    description="API interna del daemon HMS para healthcheck",
    version="0.1.0",
    docs_url=None,  # Deshabilitar docs en producción
    redoc_url=None,
    lifespan=lifespan,
)


@app.get("/health")
async def health() -> JSONResponse:
    """
    Endpoint de healthcheck.
    Verifica que el scheduler está corriendo y devuelve estado básico.
    """
    try:
        scheduler_running = check_scheduler_running()
        uptime = int(time.time() - _start_time)

        if not scheduler_running:
            return JSONResponse(
                status_code=503,
                content={
                    "status": "unhealthy",
                    "scheduler_running": False,
                    "uptime_seconds": uptime,
                    "message": "Scheduler no está corriendo"
                }
            )

        # Contar jobs activos
        jobs = get_jobs_status()
        jobs_count = len([j for j in jobs if not j["id"].startswith("__internal_")])

        return JSONResponse(
            content={
                "status": "healthy",
                "scheduler_running": True,
                "uptime_seconds": uptime,
                "jobs_count": jobs_count,
            }
        )

    except Exception as e:
        logger.error(f"❌ Error en healthcheck: {e}", exc_info=True)
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": str(e),
            }
        )


@app.get("/")
async def root() -> JSONResponse:
    """Root endpoint."""
    return JSONResponse(
        content={
            "service": "HMS Daemon",
            "version": "0.1.0",
            "endpoints": ["/health", "/reload"],
        }
    )


@app.post("/reload")
async def reload_jobs() -> JSONResponse:
    """
    Recargar jobs del scheduler.
    Útil para recargar configuración sin reiniciar el daemon.
    """
    try:
        from hms.daemon.scheduler import reload_scheduler

        reload_scheduler()

        jobs = get_jobs_status()
        return JSONResponse(
            content={
                "status": "success",
                "message": "Jobs recargados",
                "jobs_count": len(jobs),
            }
        )
    except Exception as e:
        logger.error(f"❌ Error recargando jobs: {e}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={
                "status": "error",
                "message": str(e),
            }
        )

