"""
Definición de jobs por defecto para el scheduler HMS.
Cada job incluye comando HMS a ejecutar, trigger y estado inicial.
"""

from copy import deepcopy
from typing import Dict, Any

# Definición base de jobs por defecto
DEFAULT_JOBS: Dict[str, Dict[str, Any]] = {
    "update-dns": {
        "enabled": True,
        "command": ["hms", "system", "update-dns"],
        "trigger": {
            "type": "interval",
            "minutes": 30,
        },
        "meta": {
            "description": "Actualizar DNS en Cloudflare",
        },
    },
}


def get_default_jobs() -> Dict[str, Dict[str, Any]]:
    """Obtener una copia de los jobs por defecto para evitar mutaciones accidentales."""
    return deepcopy(DEFAULT_JOBS)

