"""Helpers de rutas comunes para HMS."""

import os
from pathlib import Path
from typing import Optional


def resolve_project_root(project_root: Optional[str | Path] = None) -> Path:
    """Resolve project root sin asumir /project.
    Prioridad: arg explícito > env PROJECT_ROOT > raíz de repo (inferida).
    """
    if project_root:
        return Path(project_root)
    env_root = os.environ.get("PROJECT_ROOT")
    if env_root:
        return Path(env_root)
    # Infer repo root: lib/paths.py -> lib/ -> hms/ -> repo/
    return Path(__file__).resolve().parents[2]

