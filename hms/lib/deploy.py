"""Helpers de deploy para stacks.

Centraliza lógica compartida: validación de stack, generación de .env
(desde config/private) y ejecución de pre-deploy (sh + py). Pensado para
intercambiar la fuente de .env a OneDrive en el futuro.
"""

import subprocess
import sys
from pathlib import Path
from typing import Tuple

from hms.lib.stacks import get_stack_manager
from hms.lib.config import get_env_generator


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
    env_gen = get_env_generator()

    if not stack_manager.stack_exists(stack_name):
        raise PrepError(f"Stack '{stack_name}' no definido en stacks.yml")

    info = stack_manager.get_stack_info(stack_name)
    if not info.get("has_compose"):
        raise PrepError(f"Stack '{stack_name}' no tiene docker-compose.yml")

    stack_dir = stack_manager.get_stack_dir(stack_name)

    # Generar .env
    env_path = env_gen.generate_stack_env(stack_name)
    print(f"✅ .env generado: {env_path}")

    # Buscar pre-deploy scripts
    predeploy_py = stack_dir / "pre-deploy.py"
    predeploy_sh = stack_dir / "pre-deploy.sh"

    ran_any = False

    # Ejecutar pre-deploy.py si existe
    if predeploy_py.exists():
        print(f"🐍 Ejecutando pre-deploy.py: {predeploy_py}")
        result = subprocess.run(
            [sys.executable, str(predeploy_py), stack_name],
            cwd=str(stack_dir),
            check=False,
            text=True,
            env={
                **subprocess.os.environ,
                'STACK_NAME': stack_name,
                'PROJECT_ROOT': str(stack_manager.project_root)
            }
        )
        if result.returncode != 0:
            raise PrepError(f"pre-deploy.py falló con código {result.returncode}")
        print("✅ pre-deploy.py completado")
        ran_any = True

    # Ejecutar pre-deploy.sh si existe
    if predeploy_sh.exists():
        print(f"🔧 Ejecutando pre-deploy.sh: {predeploy_sh}")
        result = subprocess.run(
            ["bash", str(predeploy_sh)],
            cwd=str(predeploy_sh.parent),
            check=False,
            text=True,
        )
        if result.returncode != 0:
            raise PrepError(f"pre-deploy.sh falló con código {result.returncode}")
        print("✅ pre-deploy.sh completado")
        ran_any = True

    if not ran_any:
        print("ℹ️  No hay pre-deploy scripts, nada que ejecutar")

    return env_path, ran_any

