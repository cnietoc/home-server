"""Helpers de rutas comunes para HMS."""
import os
from pathlib import Path


def get_project_root() -> Path:
    """Resolve project root sin asumir /project.
    Prioridad: arg explícito > env PROJECT_ROOT > raíz de repo (inferida).
    """
    env_root = os.environ.get("PROJECT_ROOT")
    if env_root:
        return Path(env_root)
    # Infer repo root: lib/paths.py -> lib/ -> hms/ -> root/
    return Path(__file__).resolve().parents[2]


def get_hms_root() -> Path:
    """Obtiene la ruta raíz del paquete hms."""
    return Path(__file__).resolve().parents[1]


def get_logs_root() -> Path:
    return get_project_root() / "logs"


def get_config_root() -> Path:
    return get_project_root()


def get_stacks_root() -> Path:
    """Obtiene la ruta raíz de stacks de aplicación."""
    return get_project_root() / "stacks"


def get_stack_dir(stack_name: str) -> Path:
    """Obtiene la ruta del directorio de un stack específico."""
    if stack_name == "infra":
        return get_core_root() / "infra"
    return get_stacks_root() / stack_name


def get_core_root() -> Path:
    """Obtiene la ruta raíz de componentes core."""
    return get_project_root() / "core"


def get_data_root() -> Path:
    """Obtiene la ruta raíz de datos."""
    return get_project_root() / "data"
