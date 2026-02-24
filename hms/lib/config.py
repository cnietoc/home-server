"""
Gestor de configuración TOML para HMS.

Proporciona:
- Carga de config.toml como fuente única de verdad
- Valores por defecto desde config.default.toml
- Inyección dinámica de variables de entorno
- Aislamiento de configuración por stack
- Detección y validación de variables faltantes
"""

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Optional, Any, List, Literal

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

import tomlkit

from hms.lib.paths import get_config_root

logger = logging.getLogger(__name__)


@dataclass
class JobTrigger:
    type: Literal["interval", "cron", "startup"]
    config: Dict[str, str] = field(default_factory=dict)

    @property
    def value(self) -> str:
        """Devuelve el valor principal de configuración según el tipo de trigger."""
        return {
            "interval": self.config.get("interval"),
            "cron": self.config.get("cron"),
            "startup": self.config.get("delay")
        }.get(self.type)


@dataclass
class JobDefinition:
    name: str
    plugin: str
    enabled: bool = True
    description: str = ""
    args: List[Any] = field(default_factory=list)
    triggers: List[JobTrigger] = field(default_factory=list)


class TomlConfigManager:
    """Gestor de configuración TOML con soporte para defaults y validación."""

    def __init__(self):
        self._config_path = get_config_root() / "config.toml"
        self._default_config_path = get_config_root() / "config.default.toml"
        if not self._config_path.exists():
            # Crear config.toml vacío si no existe
            self._config_path.touch()

    def load_env_config(self):
        """
        Carga la configuración y cambia el UID/GID y timezone del proceso Python.

        - Cambia el UID/GID real del proceso (requiere permisos o gosu)
        - Establece el timezone del proceso
        - Actualiza variables de entorno
        """
        config = self._load_config()
        global_config = config.get("global", {})

        puid = global_config.get("puid", 1000)
        pgid = global_config.get("pgid", 1000)
        tz = global_config.get("tz", "UTC")

        import os

        # 1. Cambiar timezone del proceso
        os.environ["TZ"] = str(tz)
        try:
            import time
            time.tzset()  # Aplicar el cambio de timezone
        except Exception as e:
            logger.warning(f"No se pudo cambiar timezone: {e}")

        # 2. Cambiar UID/GID del proceso (solo si somos root o tenemos permisos)
        try:
            current_uid = os.getuid()
            current_gid = os.getgid()

            # Solo intentar cambiar si somos root (uid=0) y los valores son diferentes
            if current_uid == 0 and (current_uid != puid or current_gid != pgid):
                # Primero cambiar GID, luego UID (en ese orden por seguridad)
                os.setgid(pgid)
                os.setuid(puid)
                logger.debug(f"UID/GID cambiado a: {puid}:{pgid}")
            elif current_uid != puid or current_gid != pgid:
                logger.debug(
                    f"No se puede cambiar UID/GID (no somos root). Actual: {current_uid}:{current_gid}, Deseado: {puid}:{pgid}")
        except AttributeError:
            # getuid/setuid no disponible en Windows
            logger.debug("Cambio de UID/GID no disponible en esta plataforma")
        except Exception as e:
            logger.warning(f"No se pudo cambiar UID/GID: {e}")

        # 3. Establecer variables de entorno (para subprocesos)
        os.environ["PUID"] = str(puid)
        os.environ["PGID"] = str(pgid)

    def get_config_value(self, key: str, default: Optional[str] = None) -> str:
        """
        Obtiene el valor de configuración para una clave dada,
        considerando el stack si se proporciona.

        :param key: Clave de configuración (p.ej. "database.host")
        :param default: Valor por defecto si la clave no existe
        :return: Valor de configuración
        :raises KeyError: Si la clave no existe en la configuración
        """
        config = self._load_config()
        keys = key.split(".")
        value = config
        for k in keys:
            if k in value:
                value = value[k]
            else:
                break

        if value == "__REQUIRED__":
            raise KeyError(f"La clave de configuración requerida '{key}' no está establecida.")
        if value is None:
            if default is not None:
                return default
            else:
                raise KeyError(f"La clave de configuración '{key}' no existe.")
        return value

    def _load_config(self) -> Dict:
        """
        Carga la configuración desde config.toml y aplica defaults.

        :param stack: Nombre del stack (opcional)
        :return: Diccionario de configuración
        """
        default_config = self._load_toml_file(self._default_config_path)
        user_config = self._load_toml_file(self._config_path)

        # Merge user config over defaults
        default_config = self._merge_dicts(default_config, user_config)

        return default_config

    def _load_toml_file(self, path: Path) -> Dict:
        """Carga un archivo TOML y devuelve su contenido como diccionario."""
        if not path.exists():
            logger.warning(f"Archivo de configuración '{path}' no encontrado.")
            return {}
        with path.open("rb") as f:
            return tomllib.load(f)

    def _merge_dicts(self, default_config: Dict, user_config: Dict) -> Dict:
        """Fusiona dos diccionarios, con user_config teniendo prioridad."""
        for key, value in user_config.items():
            if (
                    key in default_config
                    and isinstance(default_config[key], dict)
                    and isinstance(value, dict)
            ):
                default_config[key] = self._merge_dicts(default_config[key], user_config[key])
            else:
                default_config[key] = value
        return default_config

    def _save_config(self, config: Dict):
        """Guarda el diccionario de configuración en config.toml."""
        toml_content = tomlkit.dumps(tomlkit.parse(tomlkit.dumps(config)))
        with self._config_path.open("w", encoding="utf-8") as f:
            f.write(toml_content)

    def _find_missing_required_keys(self, default_config: Dict, user_config: Dict, prefix: str = "") -> List[str]:
        """
        Encuentra claves marcadas como requeridas en default_config que faltan en user_config.

        :param default_config: Configuración por defecto
        :param user_config: Configuración del usuario
        :param prefix: Prefijo para claves anidadas
        :return: Lista de claves faltantes
        """
        missing_keys = []
        for key, value in default_config.items():
            full_key = f"{prefix}.{key}" if prefix else key
            if isinstance(value, dict):
                # Verificar recursivamente en sub-diccionarios
                missing_keys.extend(
                    self._find_missing_required_keys(
                        value,
                        user_config.get(key, {}),
                        prefix=full_key
                    )
                )
            else:
                # Verificar si la clave es requerida y falta en user_config
                if (
                        isinstance(value, str)
                        and value.__eq__("__REQUIRED__")
                        and key not in user_config
                ):
                    missing_keys.append(full_key)

        return missing_keys

    def _add_missing_keys_to_config(self, missing_keys: List[str], user_config: Dict):
        """
        Añade claves faltantes a user_config dejándolas como __REQUIRED__.

        :param missing_keys: Lista de claves faltantes
        :param user_config: Configuración del usuario (a modificar)
        """
        logger.debug(f"Añadiendo claves faltantes a la configuración: {missing_keys}")
        logger.debug(f"Configuración antes de añadir claves faltantes: {user_config}")
        for key in missing_keys:
            keys = key.split(".")
            current_level = user_config
            for k in keys[:-1]:
                if k not in current_level or not isinstance(current_level[k], dict):
                    current_level[k] = {}
                current_level = current_level[k]
            # Añadir la clave faltante como __REQUIRED__
            current_level[keys[-1]] = "__REQUIRED__"
        logger.debug(f"Configuración después de añadir claves faltantes: {user_config}")

    def _find_still_required_keys(self, config: Dict, prefix: str = "") -> List[str]:
        """
        Encuentra claves que siguen marcadas como __REQUIRED__ en la configuración.

        :param config: Diccionario de configuración a analizar
        :param prefix: Prefijo para claves anidadas
        :return: Lista de claves que siguen siendo requeridas
        """
        still_required = []
        for key, value in config.items():
            full_key = f"{prefix}.{key}" if prefix else key
            if isinstance(value, dict):
                # Verificar recursivamente en sub-diccionarios
                still_required.extend(
                    self._find_still_required_keys(value, prefix=full_key)
                )
            else:
                # Verificar si la clave sigue siendo __REQUIRED__
                if isinstance(value, str) and value == "__REQUIRED__":
                    still_required.append(full_key)
        return still_required

    def check_missing_global_config(self) -> List[str]:
        """
        Crea entradas faltantes en config.toml basadas en config.default.toml
        para claves marcadas como requeridas.

        También devuelve las claves que siguen marcadas como requeridas en config.toml.

        :return: Lista de claves que siguen siendo requeridas
        """
        default_config = self._load_toml_file(self._default_config_path)
        user_config = self._load_toml_file(self._config_path)

        missing_keys = self._find_missing_required_keys(default_config, user_config)

        def is_non_global_key(key: str) -> bool:
            root = key.split(".", 1)[0]
            return root not in {"global", "infra", "jobs"}

        missing_keys = [k for k in missing_keys if not is_non_global_key(k)]

        if missing_keys:
            self._add_missing_keys_to_config(missing_keys, user_config)
            self._save_config(user_config)

        # Detectar claves que siguen siendo requeridas después de las adiciones
        updated_config = self._load_toml_file(self._config_path)
        still_required_keys = self._find_still_required_keys(updated_config)
        still_required_keys = [k for k in still_required_keys if not is_non_global_key(k)]

        return still_required_keys

    def check_missing_stack_config(self, stack_name: str) -> List[str]:
        """
        Verifica claves requeridas faltantes para un stack específico.

        :param stack_name: Nombre del stack
        :return: Lista de claves que siguen siendo requeridas para el stack
        """
        default_config = self._load_toml_file(self._default_config_path)
        user_config = self._load_toml_file(self._config_path)

        stack_default_config = default_config.get(stack_name, {})
        stack_user_config = user_config.get(stack_name, {})

        prefix = stack_name
        missing_keys = self._find_missing_required_keys(
            stack_default_config,
            stack_user_config,
            prefix=prefix
        )

        if missing_keys:
            if stack_name not in user_config:
                user_config[stack_name] = {}

            self._add_missing_keys_to_config(
                missing_keys,
                user_config
            )
            self._save_config(user_config)

        # Detectar claves que siguen siendo requeridas después de las adiciones
        updated_config = self._load_toml_file(self._config_path)
        updated_stack_config = updated_config.get(stack_name, {})
        still_required_keys = self._find_still_required_keys(
            updated_stack_config,
            prefix=prefix
        )

        return still_required_keys

    def get_global_config(self) -> Dict[str, Any]:
        """
        Obtiene la configuración global desde config.toml.

        :return: Diccionario con la configuración global
        """
        config = self._load_config()

        # Quitamos de la configuración algunas claves específicas de backups y shares
        result = config.get("global", {}).copy()
        if "backups" in result:
            del result["backups"]
        if "shares" in result:
            del result["shares"]
        return result

    def get_global_backup_config(self) -> Dict[str, Any]:
        """
        Obtiene la configuración global de backups desde config.toml.

        :return: Diccionario con la configuración global de backups
        """
        config = self._load_config()

        return config.get("global", {}).get("backups", {})

    def get_stack_config(self, stack_name: str) -> Dict[str, Any]:
        """
        Obtiene la configuración específica de un stack.

        :param stack_name: Nombre del stack
        :return: Diccionario con la configuración del stack
        """
        config = self._load_config()

        result = config.get(stack_name, {}).copy()
        if "backups" in result:
            del result["backups"]
        if "shares" in result:
            del result["shares"]
        return result

    def get_stack_backup_config(self, stack_name: str) -> Dict[str, Any]:
        """
        Obtiene la configuración específica de un stack relacionada con backups.

        :param stack_name: Nombre del stack
        :return: Diccionario con la configuración del stack de backups
        """
        config = self._load_config()

        return config.get(stack_name, {}).get("backups", {})

    def is_stack_enabled(self, stack_name: str) -> bool:
        """
        Verifica si un stack está habilitado en la configuración.
        El stack 'infra' siempre está habilitado por defecto.

        :param stack_name: Nombre del stack
        :return: True si está habilitado, False en caso contrario
        """
        # Stack infra siempre está activo por defecto
        if stack_name == "infra":
            stack_config = self.get_stack_config(stack_name)
            # Permitir deshabilitar infra explícitamente si alguien lo necesita
            return stack_config.get("enabled", True)

        stack_config = self.get_stack_config(stack_name)
        return stack_config.get("enabled", False)

    def enable_stack(self, stack_name: str):
        """
        Habilita un stack en la configuración.

        :param stack_name: Nombre del stack
        """
        config = self._load_toml_file(self._config_path)

        if stack_name == "infra":
            del config[stack_name]["enabled"]
        else:
            if stack_name not in config:
                config[stack_name] = {}

            config[stack_name]["enabled"] = True

        self._save_config(config)

    def disable_stack(self, stack_name: str):
        """
        Deshabilita un stack en la configuración.

        :param stack_name: Nombre del stack
        """
        config = self._load_toml_file(self._config_path)

        if stack_name == "infra":
            config[stack_name]["enabled"] = False
        else:
            if stack_name not in config:
                config[stack_name] = {}

            if "enabled" in config[stack_name]:
                del config[stack_name]["enabled"]

        self._save_config(config)

    def get_job_definitions(self) -> List[JobDefinition]:
        """
        Nueva API: devuelve lista de JobDefinition desde `[jobs.<name>]`.
        Cada trigger puede ser objeto o lista de objetos.
        No altera el flujo actual; solo expone la estructura tipada.
        """
        config = self._load_config()
        jobs_cfg = config.get("jobs", {}) or {}

        result: List[JobDefinition] = []
        for name, cfg in jobs_cfg.items():
            if not isinstance(cfg, dict):
                logger.warning(f"Job '{name}' ignorado: config no es un objeto")
                continue

            plugin = cfg.get("plugin")
            if not plugin:
                logger.warning(f"Job '{name}' ignorado: falta 'plugin'")
                continue

            raw_triggers = cfg.get("triggers") or []
            if isinstance(raw_triggers, dict):
                raw_triggers = [raw_triggers]

            triggers: List[JobTrigger] = []
            for trig in raw_triggers:
                if not isinstance(trig, dict):
                    logger.warning(f"Trigger inválido en job '{name}': {trig}")
                    continue
                trig_type = trig.get("type")
                if not trig_type:
                    logger.warning(f"Trigger sin 'type' en job '{name}': {trig}")
                    continue
                trig_config = {k: v for k, v in trig.items() if k != "type"}
                triggers.append(JobTrigger(type=trig_type, config=trig_config))

            result.append(
                JobDefinition(
                    name=name,
                    plugin=plugin,
                    enabled=cfg.get("enabled", True),
                    description=cfg.get("description", ""),
                    args=cfg.get("args", []) or [],
                    triggers=triggers,
                )
            )

        return result


config_manager = TomlConfigManager()
