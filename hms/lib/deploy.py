"""Helpers de deploy para stacks.

Centraliza lógica compartida: validación de stack, generación de .env
(desde config/private) y ejecución de pre-deploy (sh + py). Pensado para
intercambiar la fuente de .env a OneDrive en el futuro.
"""

import logging
import subprocess
import sys
from pathlib import Path
from typing import Tuple

from hms.lib.config import get_env_manager
from hms.lib.stacks import get_stack_manager

logger = logging.getLogger(__name__)


class PrepError(Exception):
    pass


def prep_stack(stack_name: str) -> Tuple[Path, bool]:
    """
    Prepara un stack: valida, genera .env y ejecuta pre-deploy si existe.

    Busca y ejecuta automáticamente:
    - docker/<stack>/pre-deploy.py (si existe)
    - docker/<stack>/pre-deploy.sh (si existe)

    Ambos se ejecutan en orden: primero .py, luego .sh

    Returns:
        (env_path, ran_predeploy)
    Raises:
        PrepError: si el stack no está definido o falta docker-compose.yml
    """
    stack_manager = get_stack_manager()
    env_manager = get_env_manager()

    if not stack_manager.stack_exists(stack_name):
        raise PrepError(f"Stack '{stack_name}' no definido en stacks.yml")

    info = stack_manager.get_stack_info(stack_name)
    if not info.get("has_compose"):
        raise PrepError(f"Stack '{stack_name}' no tiene docker-compose.yml")

    stack_dir = stack_manager.get_stack_docker_dir(stack_name)

    # Generar .env
    env_path = env_manager.generate_stack_env(stack_name)
    logger.info(f"✅ .env generado: {env_path}")

    # Buscar pre-deploy scripts
    predeploy_py = stack_dir / "pre-deploy.py"
    predeploy_sh = stack_dir / "pre-deploy.sh"

    ran_any = False

    # Ejecutar pre-deploy.py si existe
    if predeploy_py.exists():
        logger.info(f"🐍 Ejecutando pre-deploy.py: {predeploy_py}")
        result = subprocess.run(
            [sys.executable, str(predeploy_py), stack_name],
            cwd=str(stack_dir),
            check=False,
            text=True,
            env={
                **subprocess.os.environ,
                'STACK_NAME': stack_name
            }
        )
        if result.returncode != 0:
            raise PrepError(f"pre-deploy.py falló con código {result.returncode}")
        logger.info("✅ pre-deploy.py completado")
        ran_any = True

    # Ejecutar pre-deploy.sh si existe
    if predeploy_sh.exists():
        logger.info(f"🔧 Ejecutando pre-deploy.sh: {predeploy_sh}")
        result = subprocess.run(
            ["bash", str(predeploy_sh)],
            cwd=str(predeploy_sh.parent),
            check=False,
            text=True,
        )
        if result.returncode != 0:
            raise PrepError(f"pre-deploy.sh falló con código {result.returncode}")
        logger.info("✅ pre-deploy.sh completado")
        ran_any = True

    if not ran_any:
        logger.info("ℹ️  No hay pre-deploy scripts, nada que ejecutar")

    return env_path, ran_any
