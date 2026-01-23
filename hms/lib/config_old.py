"""Loaders de configuración para HMS.

Proporciona acceso a:
- config/hms.yml (config global)
- config/stacks/<stack>.yml (config por stack)
- stacks/<stack>/stack.yml (metadatos de orquestación por stack)
- core/infra/stack.yml (metadatos de infraestructura)

DEPRECATED:
- config/registry.yml (usar stack.yml individuales)
- config/stacks.yml (usar stack.yml individuales)
"""

from pathlib import Path
from typing import List, Any, Callable
import os
import subprocess
import time
import yaml

from hms.lib.paths import get_config_root, get_stacks_root
from hms.lib.stacks_old import get_stack_manager
from .secrets import SecretsManager


class YamlFileCache:
    """
    Cache para archivos YAML con TTL (Time To Live).
    Útil para evitar lecturas repetidas de disco en un período corto.
    """

    def __init__(self, ttl_seconds:  int = 300):
        """
        Inicializa el cache.

        Args:
            ttl_seconds: Tiempo de vida del cache en segundos (default: 300 = 5 minutos)
        """
        self._cache = {}  # {key: (data, timestamp)}
        self._ttl = ttl_seconds

    def get(self, key: str, loader: Callable[[], Any]) -> Any:
        """
        Obtiene un valor de cache o lo carga si no existe o ha expirado.

        Args:
            key: Clave del cache
            loader: Función que carga el dato si no está en cache o ha expirado

        Returns:
            El valor cacheado o recién cargado
        """
        current_time = time.time()

        # Verificar si existe en cache y no ha expirado
        if key in self._cache:
            data, timestamp = self._cache[key]
            if current_time - timestamp < self._ttl:
                return data

        # Cargar desde disco y cachear
        data = loader()
        self._cache[key] = (data, current_time)
        return data

    def invalidate(self, key: str = None):
        """
        Invalida cache. Si key es None, limpia todo el cache.

        Args:
            key: Clave específica a invalidar, o None para limpiar todo
        """
        if key is None:
            self._cache.clear()
        elif key in self._cache:
            del self._cache[key]

    def clear(self):
        """Limpia todo el cache."""
        self._cache.clear()


class _HmsConfig:
    """Loader para config/hms.yml (config global)"""

    def __init__(self):
        self._cache = YamlFileCache(ttl_seconds=300)  # 5 minutos

    def load(self) -> dict:
        """
        Carga config/hms.yml y retorna estructura YAML original (NO aplanada).
        Falla si el fichero no existe o estructura inválida.
        Cachea el resultado por 5 minutos.

        Returns:
            Dict con estructura YAML original

        Raises:
            FileNotFoundError: Si config/hms.yml no existe
            ValueError: Si faltan keys requeridas
        """
        return self._cache.get('hms_config', self._load_from_disk)

    def _load_from_disk(self) -> dict:
        """Carga efectiva desde disco."""
        config_file = get_config_root() / "hms.yml"
        if not config_file.exists():
            raise FileNotFoundError(
                f"Config file not found: {config_file}\n"
                f"Run 'hms setup init' to create from template"
            )

        with open(config_file) as f:
            data = yaml.safe_load(f)

        return data

    def clear_cache(self):
        """Limpia el cache."""
        self._cache.clear()


class _StackConfig:
    """Loader para config/stacks/<stack>.yml (config por stack)"""

    def __init__(self):
        self._cache = YamlFileCache(ttl_seconds=300)  # 5 minutos

    def load(self, stack_name: str) -> dict:
        """
        Carga config/stacks/<stack>.yml y retorna estructura YAML original.
        Retorna {} vacío si no existe (config por stack es opcional).
        Cachea el resultado por 5 minutos.

        Args:
            stack_name: Nombre del stack

        Returns:
            Dict con estructura YAML original, o {} si no existe
        """
        return self._cache.get(f'stack:{stack_name}', lambda: self._load_from_disk(stack_name))

    def _load_from_disk(self, stack_name: str) -> dict:
        """Carga efectiva desde disco."""
        config_file = get_config_root() / "stacks" / f"{stack_name}.yml"
        if not config_file.exists():
            return {}

        with open(config_file) as f:
            data = yaml.safe_load(f) or {}

        return data

    def clear_cache(self, stack_name: str = None):
        """
        Limpia el cache. Si stack_name se especifica, solo limpia ese stack.

        Args:
            stack_name: Stack específico a limpiar, o None para limpiar todo
        """
        if stack_name:
            self._cache.invalidate(f'stack:{stack_name}')
        else:
            self._cache.clear()


class Registry:
    """Loader para config/registry.yml (metadatos de stacks)"""

    def __init__(self):
        self._registry_file = get_config_root() / "registry.yml"
        self._cache = YamlFileCache(ttl_seconds=300)  # 5 minutos

    def load(self) -> dict:
        """
        Carga config/registry.yml y retorna estructura completa.
        Cachea el resultado por 5 minutos.

        Returns:
            Dict con estructura completa del registry

        Raises:
            FileNotFoundError: Si registry.yml no existe
            ValueError: Si falta la key 'stacks'
        """
        return self._cache.get('registry', self._load_from_disk)

    def _load_from_disk(self) -> dict:
        """Carga efectiva desde disco."""
        if not self._registry_file.exists():
            raise FileNotFoundError(
                f"Registry file not found: {self._registry_file}\n"
                f"Run 'hms setup init' to create from template"
            )

        with open(self._registry_file) as f:
            data = yaml.safe_load(f)

        if 'stacks' not in data:
            raise ValueError("Invalid registry.yml: missing 'stacks' key")

        return data

    def get_stack_metadata(self, stack_name: str) -> dict:
        """Retorna metadatos de un stack específico"""
        registry = self.load()
        return registry.get('stacks', {}).get(stack_name, {})

    def list_stacks(self) -> list[str]:
        """Lista todos los stacks definidos en registry"""
        registry = self.load()
        return list(registry.get('stacks', {}).keys())

    def stack_exists(self, stack_name: str) -> bool:
        """Comprueba si un stack está definido en registry"""
        return stack_name in self.list_stacks()

    def clear_cache(self):
        """Limpia el cache."""
        self._cache.clear()


def _flatten_dict(d: dict, parent_key: str = '', sep: str = '_') -> dict:
    """
    Aplana dict anidado a propiedades planas para .env.

    Args:
        d: Dict a aplanar
        parent_key: Prefijo para keys anidadas
        sep: Separador entre niveles

    Returns:
        Dict aplanado con keys en MAYÚSCULAS

    Examples:
        >>> _flatten_dict({'ssh': {'user': 'admin'}})
        {'SSH_USER': 'admin'}

        >>> _flatten_dict({'network': {'subnet': '172.20.0.0/16'}})
        {'NETWORK_SUBNET': '172.20.0.0/16'}

    Manejo especial:
        - Listas → CSV: ['a', 'b'] → 'a,b'
        - Booleanos → lowercase string: True → 'true'
        - None → string vacío: None → ''
    """
    items = []

    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}".upper() if parent_key else k.upper()

        if isinstance(v, dict):
            # Recursivo para objetos anidados
            items.extend(_flatten_dict(v, new_key, sep=sep).items())
        elif isinstance(v, list):
            # Listas → CSV string
            items.append((new_key, ','.join(str(x) for x in v)))
        elif isinstance(v, bool):
            # Booleanos → lowercase string
            items.append((new_key, str(v).lower()))
        elif v is None:
            # None → string vacío
            items.append((new_key, ''))
        else:
            # Valores primitivos → string
            items.append((new_key, str(v)))

    return dict(items)


# Mantener compatibilidad temporal con código existente
class EnvManager:
    def __init__(self, project_root: Path | None = None) -> None:
        self._stack_manager = get_stack_manager()
        self._config_dir = get_config_root() / "private"

    def _get_system_timezone(self) -> str:
        """Detecta el timezone del sistema actual.
        Intenta múltiples métodos para máxima compatibilidad.
        """
        # Método 1: Variable de entorno TZ
        tz = os.environ.get('TZ')
        if tz:
            return tz

        # Método 2: /etc/timezone (Linux)
        tz_file = Path('/etc/timezone')
        if tz_file.exists():
            return tz_file.read_text().strip()

        # Método 3: /etc/localtime symlink (Linux/macOS)
        localtime = Path('/etc/localtime')
        if localtime.is_symlink():
            target = os.readlink(str(localtime))
            # Extraer timezone de rutas como /usr/share/zoneinfo/Europe/Madrid
            for prefix in ['/var/db/timezone/zoneinfo/', '/usr/share/zoneinfo/']:
                if prefix in target:
                    return target.split(prefix)[1]

        # Método 4: systemd (Linux)
        try:
            result = subprocess.run(
                ['timedatectl', 'show', '-p', 'Timezone', '--value'],
                capture_output=True,
                text=True,
                timeout=1
            )
            if result.returncode == 0:
                tz = result.stdout.strip()
                if tz:
                    return tz
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

        # Fallback: UTC
        return 'UTC'

    def _read_env_file(self, name: str) -> List[str]:
        """Lee un archivo .env desde config/private/<name>.env.
        Si no existe, devuelve lista vacía.
        """
        path = self._config_dir / f"{name}.env"
        if not path.exists():
            return []
        return path.read_text().splitlines()


    def get_env_value(self, config_name: str, key: str) -> str | None:
        """Devuelve el valor de `key` desde las configs privadas.
        Ignora comentarios y líneas vacías; devuelve None si no se encuentra.
        Deprecado: usar Config.get_value() en su lugar.
        """
        for raw_line in self._read_env_file(config_name):
            line = raw_line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' not in line:
                continue
            current_key, value = line.split('=', 1)
            if current_key.strip() == key:
                return value
        return None

    def generate_stack_env(self, stack_name: str) -> Path:
        """Genera stacks/<stack>/.env combinando common.env y los envs declarados en stack.yml.
        Retorna la ruta del archivo generado.
        """
        info = self._stack_manager.get_stack_info(stack_name)
        # Si el stack no existe en stack.yml, fallamos explícitamente
        if not self._stack_manager.stack_exists(stack_name):
            raise ValueError(f"Stack '{stack_name}' no definido en stack.yml")

        stack_dir = self._stack_manager.get_stack_docker_dir(stack_name)
        target_env = stack_dir / ".env"
        target_env.parent.mkdir(parents=True, exist_ok=True)

        # common.env siempre primero, luego los específicos del stack
        env_names = ["common"] + info.get("config_files", [])
        if not info.get("config_files"):
            # fallback: si no hay config_files declarados, intenta stack_name
            env_names.append(stack_name)

        lines: List[str] = []

        # Variables dinámicas del stack
        data_dir = get_stack_manager().get_stack_data_dir(stack_name)
        relative_data = os.path.relpath(data_dir, stack_dir)
        lines.append("# Variables dinámicas del stack")
        lines.append(f"STACK_NAME={stack_name}")
        lines.append(f"STACK_PREFIX=hms-{stack_name}")
        lines.append(f"STACK_DATA={relative_data}")
        lines.append("")

        # Variables del sistema dinámicas
        lines.append("# Variables del sistema (dinámicas)")
        lines.append(f"PUID={os.getuid()}")
        lines.append(f"PGID={os.getgid()}")
        lines.append(f"TZ={self._get_system_timezone()}")
        lines.append("")

        for name in env_names:
            file_lines = self._read_env_file(name)
            if file_lines:
                lines.append(f"# Source: {name}.env")
                lines.extend(file_lines)
                lines.append("")

        target_env.write_text("\n".join(lines).rstrip() + "\n")
        return target_env


class Config:
    """
    Acceso centralizado a config y secretos con API basada en paths YAML.
    Estado (data/state.yml) se gestiona aparte con get_state_manager().

    Uso:
        domain = config.get('domain', source='config')
        token = config.get('cloudflare.dns_api_token', source='secrets')
        hardware = config.get('hardware_accel.amd_vaapi', source='config:media')
    """

    def __init__(self):
        self._registry = Registry()
        self._hms_config = _HmsConfig()
        self._stack_config = _StackConfig()
        self._secrets_manager = SecretsManager()

    def get_value(self, path: str, source: str, default: str = None) -> str:
        """
        Obtiene un valor individual de una fuente específica usando path YAML.

        Args:
            path: Path del valor en YAML (ej: 'cloudflare.email', 'domain')
            source: Fuente explícita:
                    - 'config' → config/hms.yml
                    - 'config:<stack>' → config/stacks/<stack>.yml
                    - 'secrets' → secrets/platform.yml (OneDrive)
                    - 'secrets:<stack>' → secrets/stacks/<stack>.yml (OneDrive)
                    - 'registry' → config/registry.yml
            default: Valor por defecto si no se encuentra

        Returns:
            El valor encontrado como string, o default

        Raises:
            ValueError: Si la fuente no es válida

        Examples:
            >>> config.get_value('domain', source='config')
            'asdf.net'
            >>> config.get_value('cloudflare.email', source='secrets')
            'asdf@gmail.com'
        """
        return self._get_data(path, source, default)

    def get_branch(self, path: str, source: str, default: dict = None) -> dict:
        """
        Obtiene toda una rama/sección del YAML de una fuente específica.

        Args:
            path: Path de la rama en YAML (ej: 'cloudflare', 'network', 'hardware_accel')
            source: Fuente explícita (mismo formato que get_value)
            default: Dict por defecto si no se encuentra

        Returns:
            Dict con toda la rama del YAML, o default

        Raises:
            ValueError: Si la fuente no es válida

        Examples:
            >>> config.get_branch('network', source='config')
            {'name': 'proxy', 'subnet': '172.20.0.0/16'}
            >>> config.get_branch('cloudflare', source='secrets')
            {'email': 'asdf@gmail.com', 'dns_api_token': 'rzmT...'}
            >>> config.get_branch('hardware_accel', source='config:media')
            {'intel_qsv': False, 'nvidia': False, 'amd_vaapi': True}
        """
        result = self._get_data(path, source, default)

        # Asegurar que devolvemos un dict
        if not isinstance(result, dict):
            return default if default is not None else {}

        return result

    def _get_data(self, path: str, source: str, default: Any = None) -> Any:
        """
        Método interno para obtener datos de una fuente específica.
        Usado tanto por get_value() como por get_branch().

        Args:
            path: Path del valor en YAML
            source: Fuente explícita
            default: Valor por defecto

        Returns:
            El dato encontrado (puede ser str, int, dict, list, etc.) o default
        """
        if source == 'config':
            data = self._load_hms_config()
        elif source.startswith('config:'):
            stack_name = source.split(':', 1)[1]
            data = self._load_stack_config(stack_name)
        elif source == 'secrets':
            data = self._secrets_manager.fetch_platform_secrets_as_dict()
        elif source.startswith('secrets:'):
            stack_name = source.split(':', 1)[1]
            data = self._secrets_manager.fetch_stack_secrets_as_dict(stack_name)
        elif source == 'registry':
            registry_data = self._registry.load()
            return self._get_nested(registry_data, path, default)
        else:
            raise ValueError(
                f"Invalid source: {source}\n"
                f"Valid sources: config, config:<stack>, secrets, secrets:<stack>, registry"
            )

        return self._get_nested(data, path, default)

    def _get_nested(self, data: dict, path: str, default: Any = None) -> Any:
        """
        Obtiene valor anidado usando dot notation.
        """
        keys = path.split('.')
        current = data

        for key in keys:
            if isinstance(current, dict) and key in current:
                current = current[key]
            else:
                return default

        return current

    def _load_hms_config(self) -> dict:
        """Carga config/hms.yml (cached con TTL 5min)"""
        return self._hms_config.load()

    def _load_stack_config(self, stack_name: str) -> dict:
        """Carga config/stacks/<stack>.yml (cached con TTL 5min)"""
        return self._stack_config.load(stack_name)

    def _registry(self) -> Registry:
        """Acceso directo al Registry (para métodos específicos)"""
        return self._registry

    def _clear_cache(self):
        """Limpia cache de config (útil para testing)"""
        self._hms_config.clear_cache()
        self._stack_config.clear_cache()
        self._registry.clear_cache()
        self._secrets_manager.clear_cache()


config = Config()
env_manager = EnvManager()
