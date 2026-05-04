"""
TOML configuration manager for HMS.

Provides:
- Loading config.toml as the single source of truth
- Default values from config.default.toml
- Dynamic environment variable injection
- Per-stack configuration isolation
- Detection and validation of missing variables
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

_SECRET_KEYS = {"token", "secret", "password", "api_key", "api_token", "key", "passwd", "pass"}


def _redact(d: Any) -> Any:
    """Return a copy of d with values of sensitive keys replaced by '***'."""
    if isinstance(d, dict):
        return {
            k: "***" if k.lower() in _SECRET_KEYS else _redact(v)
            for k, v in d.items()
        }
    if isinstance(d, list):
        return [_redact(i) for i in d]
    return d


@dataclass
class JobTrigger:
    type: Literal["interval", "cron", "startup"]
    config: Dict[str, str] = field(default_factory=dict)

    @property
    def value(self) -> str:
        """Returns the primary configuration value for the trigger type."""
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
    """TOML configuration manager with defaults and validation support."""

    def __init__(self):
        self._config_path = get_config_root() / "config.toml"
        self._default_config_path = get_config_root() / "config.default.toml"
        if not self._config_path.exists():
            # Create an empty config.toml if it doesn't exist
            self._config_path.touch()

    def load_env_config(self):
        """
        Loads configuration and changes the UID/GID and timezone of the Python process.

        - Changes the real UID/GID of the process (requires permissions or gosu)
        - Sets the process timezone
        - Updates environment variables
        """
        config = self._load_config()
        global_config = config.get("global", {})

        puid = global_config.get("puid", 1000)
        pgid = global_config.get("pgid", 1000)
        tz = global_config.get("tz", "UTC")

        import os

        # 1. Change the process timezone
        os.environ["TZ"] = str(tz)
        try:
            import time
            time.tzset()  # Apply the timezone change
        except Exception as e:
            logger.warning(f"Could not change timezone: {e}")

        # 2. Change the process UID/GID (only if we are root or have permissions)
        try:
            current_uid = os.getuid()
            current_gid = os.getgid()

            # Only attempt to change if we are root (uid=0) and values differ
            if current_uid == 0 and (current_uid != puid or current_gid != pgid):
                # Change GID first, then UID (order matters for security)
                os.setgid(pgid)
                os.setuid(puid)
                logger.debug(f"UID/GID changed to: {puid}:{pgid}")
            elif current_uid != puid or current_gid != pgid:
                logger.debug(
                    f"Cannot change UID/GID (not root). Current: {current_uid}:{current_gid}, Desired: {puid}:{pgid}")
        except AttributeError:
            # getuid/setuid not available on Windows
            logger.debug("UID/GID change not available on this platform")
        except Exception as e:
            logger.warning(f"Could not change UID/GID: {e}")

        # 3. Set environment variables (for subprocesses)
        os.environ["PUID"] = str(puid)
        os.environ["PGID"] = str(pgid)

    def get_config_value(self, key: str, default: Optional[str] = None) -> str:
        """
        Returns the configuration value for a given key.

        :param key: Configuration key (e.g. "database.host")
        :param default: Default value if the key does not exist
        :return: Configuration value
        :raises KeyError: If the key does not exist in the configuration
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
            raise KeyError(f"Required configuration key '{key}' is not set.")
        if value is None:
            if default is not None:
                return default
            else:
                raise KeyError(f"Configuration key '{key}' does not exist.")
        return value

    def _load_config(self) -> Dict:
        """
        Loads configuration from config.toml and applies defaults.

        :return: Configuration dictionary
        """
        default_config = self._load_toml_file(self._default_config_path)
        user_config = self._load_toml_file(self._config_path)

        # Merge user config over defaults
        default_config = self._merge_dicts(default_config, user_config)

        return default_config

    def _load_toml_file(self, path: Path) -> Dict:
        """Loads a TOML file and returns its contents as a dictionary."""
        if not path.exists():
            logger.warning(f"Configuration file '{path}' not found.")
            return {}
        with path.open("rb") as f:
            return tomllib.load(f)

    def _merge_dicts(self, default_config: Dict, user_config: Dict) -> Dict:
        """Merges two dictionaries, with user_config taking priority."""
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
        """Saves the configuration dictionary to config.toml."""
        toml_content = tomlkit.dumps(tomlkit.parse(tomlkit.dumps(config)))
        with self._config_path.open("w", encoding="utf-8") as f:
            f.write(toml_content)

    def _find_missing_required_keys(self, default_config: Dict, user_config: Dict, prefix: str = "") -> List[str]:
        """
        Finds keys marked as required in default_config that are missing from user_config.

        :param default_config: Default configuration
        :param user_config: User configuration
        :param prefix: Prefix for nested keys
        :return: List of missing keys
        """
        missing_keys = []
        for key, value in default_config.items():
            full_key = f"{prefix}.{key}" if prefix else key
            if isinstance(value, dict):
                # Recursively check sub-dictionaries
                missing_keys.extend(
                    self._find_missing_required_keys(
                        value,
                        user_config.get(key, {}),
                        prefix=full_key
                    )
                )
            else:
                # Check if the key is required and missing from user_config
                if (
                        isinstance(value, str)
                        and value.__eq__("__REQUIRED__")
                        and key not in user_config
                ):
                    missing_keys.append(full_key)

        return missing_keys

    def _add_missing_keys_to_config(self, missing_keys: List[str], user_config: Dict):
        """
        Adds missing keys to user_config leaving them as __REQUIRED__.

        :param missing_keys: List of missing keys
        :param user_config: User configuration (to be modified)
        """
        logger.debug(f"Adding missing keys to configuration: {missing_keys}")
        logger.debug(f"Configuration before adding missing keys: {_redact(user_config)}")
        for key in missing_keys:
            keys = key.split(".")
            current_level = user_config
            for k in keys[:-1]:
                if k not in current_level or not isinstance(current_level[k], dict):
                    current_level[k] = {}
                current_level = current_level[k]
            # Add the missing key as __REQUIRED__
            current_level[keys[-1]] = "__REQUIRED__"
        logger.debug(f"Configuration after adding missing keys: {_redact(user_config)}")

    def _find_still_required_keys(self, config: Dict, prefix: str = "") -> List[str]:
        """
        Finds keys that are still marked as __REQUIRED__ in the configuration.

        :param config: Configuration dictionary to analyse
        :param prefix: Prefix for nested keys
        :return: List of keys that are still required
        """
        still_required = []
        for key, value in config.items():
            full_key = f"{prefix}.{key}" if prefix else key
            if isinstance(value, dict):
                # Recursively check sub-dictionaries
                still_required.extend(
                    self._find_still_required_keys(value, prefix=full_key)
                )
            else:
                # Check if the key is still __REQUIRED__
                if isinstance(value, str) and value == "__REQUIRED__":
                    still_required.append(full_key)
        return still_required

    def check_missing_global_config(self) -> List[str]:
        """
        Creates missing entries in config.toml based on config.default.toml
        for keys marked as required.

        Also returns keys that are still marked as required in config.toml.

        :return: List of keys that are still required
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

        # Detect keys that are still required after the additions
        updated_config = self._load_toml_file(self._config_path)
        still_required_keys = self._find_still_required_keys(updated_config)
        still_required_keys = [k for k in still_required_keys if not is_non_global_key(k)]

        return still_required_keys

    def check_missing_stack_config(self, stack_name: str) -> List[str]:
        """
        Checks for missing required keys for a specific stack.

        :param stack_name: Stack name
        :return: List of keys that are still required for the stack
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

        # Detect keys that are still required after the additions
        updated_config = self._load_toml_file(self._config_path)
        updated_stack_config = updated_config.get(stack_name, {})
        still_required_keys = self._find_still_required_keys(
            updated_stack_config,
            prefix=prefix
        )

        return still_required_keys

    def get_global_config(self) -> Dict[str, Any]:
        """
        Returns the global configuration from config.toml.

        :return: Dictionary with the global configuration
        """
        config = self._load_config()

        # Remove certain backup- and share-specific keys from the configuration
        result = config.get("global", {}).copy()
        if "backups" in result:
            del result["backups"]
        if "shares" in result:
            del result["shares"]
        return result

    def get_global_backup_config(self) -> Dict[str, Any]:
        """
        Returns the global backup configuration from config.toml.

        :return: Dictionary with the global backup configuration
        """
        config = self._load_config()

        return config.get("global", {}).get("backups", {})

    def get_stack_config(self, stack_name: str) -> Dict[str, Any]:
        """
        Returns the specific configuration for a stack.

        :param stack_name: Stack name
        :return: Dictionary with the stack configuration
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
        Returns the backup-related configuration for a specific stack.

        :param stack_name: Stack name
        :return: Dictionary with the stack backup configuration
        """
        config = self._load_config()

        return config.get(stack_name, {}).get("backups", {})

    def is_stack_enabled(self, stack_name: str) -> bool:
        """
        Checks whether a stack is enabled in the configuration.
        The 'infra' stack is always enabled by default.

        :param stack_name: Stack name
        :return: True if enabled, False otherwise
        """
        # The infra stack is always active by default
        if stack_name == "infra":
            stack_config = self.get_stack_config(stack_name)
            # Allow explicitly disabling infra if needed
            return stack_config.get("enabled", True)

        stack_config = self.get_stack_config(stack_name)
        return stack_config.get("enabled", False)

    def enable_stack(self, stack_name: str):
        """
        Enables a stack in the configuration.

        :param stack_name: Stack name
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
        Disables a stack in the configuration.

        :param stack_name: Stack name
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

    def get_router_config(self) -> Dict[str, Any]:
        """Returns the [router] section of config.toml (with defaults applied)."""
        config = self._load_config()
        return config.get("router", {})

    def get_job_definitions(self) -> List[JobDefinition]:
        """
        New API: returns a list of JobDefinition from `[jobs.<name>]`.
        Each trigger can be an object or a list of objects.
        Does not alter the current flow; only exposes the typed structure.
        """
        config = self._load_config()
        jobs_cfg = config.get("jobs", {}) or {}

        result: List[JobDefinition] = []
        for name, cfg in jobs_cfg.items():
            if not isinstance(cfg, dict):
                logger.warning(f"Job '{name}' ignored: config is not an object")
                continue

            plugin = cfg.get("plugin")
            if not plugin:
                logger.warning(f"Job '{name}' ignored: missing 'plugin'")
                continue

            raw_triggers = cfg.get("triggers") or []
            if isinstance(raw_triggers, dict):
                raw_triggers = [raw_triggers]

            triggers: List[JobTrigger] = []
            for trig in raw_triggers:
                if not isinstance(trig, dict):
                    logger.warning(f"Invalid trigger in job '{name}': {trig}")
                    continue
                trig_type = trig.get("type")
                if not trig_type:
                    logger.warning(f"Trigger missing 'type' in job '{name}': {trig}")
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
