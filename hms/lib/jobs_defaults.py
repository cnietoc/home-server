"""
Definición de jobs por defecto para el scheduler HMS.
Cada job incluye especificación del plugin, trigger y estado inicial.
"""

from copy import deepcopy
from typing import Dict, Any

# Definición base de jobs por defecto
DEFAULT_JOBS: Dict[str, Dict[str, Any]] = {
    "update-dns": {
        "enabled": True,
        "plugin": "system:update-dns",
        "startup_trigger": {
            "delay_seconds": 30,
        },
        "trigger": {
            "type": "interval",
            "interval": "30m",
        },
        "args": [],
        "meta": {
            "description": "Actualizar DNS en Cloudflare",
        },
    },
}


def get_default_jobs() -> Dict[str, Dict[str, Any]]:
    """Obtener una copia de los jobs por defecto para evitar mutaciones accidentales."""
    return deepcopy(DEFAULT_JOBS)

