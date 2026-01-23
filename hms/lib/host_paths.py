from pathlib import Path

from hms.lib.config import config_manager


def get_host_stack_dir(stack_name: str) -> Path:
    """Obtiene la ruta del directorio de un stack específico en el host."""
    host_root = config_manager.get_config_value("global.host_root")  # Asegura carga de config
    if stack_name == "infra":
        return Path(host_root) / "core" / "infra"
    return Path(host_root) / "stacks" / stack_name


def get_host_data_dir(stack_name: str) -> Path:
    """Obtiene la ruta del directorio de datos en el host para un stack específico."""
    host_root = config_manager.get_config_value("global.host_root")  # Asegura carga de config
    return Path(host_root) / "data" / stack_name
