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
    root = os.environ.get("HMS_ROOT")
    if root:
        return Path(root)
    return Path(__file__).resolve().parents[1]


def get_config_root() -> Path:
    root = os.environ.get("CONFIG_ROOT")
    if root:
        return Path(root)
    return get_project_root() / "config"


def get_docker_root() -> Path:
    root = os.environ.get("DOCKER_ROOT")
    if root:
        return Path(root)
    return get_project_root() / "docker"


def get_data_root() -> Path:
    root = os.environ.get("DATA_ROOT")
    if root:
        return Path(root)
    return get_project_root() / "data"
