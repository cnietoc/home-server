"""
Default job definitions for the HMS scheduler.
Each job includes the plugin specification, trigger, and initial state.
"""

from copy import deepcopy
from typing import Dict, Any

# Base definition of default jobs
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
            "description": "Update DNS records in Cloudflare",
        },
    },
}


def get_default_jobs() -> Dict[str, Dict[str, Any]]:
    """Return a deep copy of the default jobs to avoid accidental mutations."""
    return deepcopy(DEFAULT_JOBS)
