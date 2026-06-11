"""Common path helpers for HMS."""

import os
from pathlib import Path


def get_project_root() -> Path:
    """Resolve the project root without assuming /project.
    Priority: explicit arg > env PROJECT_ROOT > inferred repo root.
    """
    env_root = os.environ.get("PROJECT_ROOT")
    if env_root:
        return Path(env_root)
    # Infer repo root: lib/paths.py -> lib/ -> hms/ -> root/
    return Path(__file__).resolve().parents[2]


def get_hms_root() -> Path:
    """Return the root path of the hms package."""
    return Path(__file__).resolve().parents[1]


def get_logs_root() -> Path:
    return get_project_root() / "logs"


def get_config_root() -> Path:
    return get_project_root()


def get_stacks_root() -> Path:
    """Return the root path of application stacks."""
    return get_project_root() / "stacks"


def get_stack_dir(stack_name: str) -> Path:
    """Return the directory path for a specific stack."""
    if stack_name == "infra":
        return get_core_root() / "infra"
    return get_stacks_root() / stack_name


def get_core_root() -> Path:
    """Return the root path of core components."""
    return get_project_root() / "core"


def get_data_root() -> Path:
    """Return the root path for data."""
    return get_project_root() / "data"
