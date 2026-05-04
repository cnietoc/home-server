from pathlib import Path

from hms.lib.config import config_manager


def get_host_stack_dir(stack_name: str) -> Path:
    """Returns the path to a specific stack's directory on the host."""
    host_root = config_manager.get_config_value("global.host_root")  # Ensures config is loaded
    if stack_name == "infra":
        return Path(host_root) / "core" / "infra"
    return Path(host_root) / "stacks" / stack_name


def get_host_data_dir(stack_name: str) -> Path:
    """Returns the path to a specific stack's data directory on the host."""
    host_root = config_manager.get_config_value("global.host_root")  # Ensures config is loaded
    return Path(host_root) / "data" / stack_name
