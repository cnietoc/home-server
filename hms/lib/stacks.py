import logging
from pathlib import Path

import yaml

from hms.lib.host_paths import get_host_stack_dir, get_host_data_dir
from hms.lib.paths import get_stacks_root, get_core_root, get_stack_dir, get_data_root

logger = logging.getLogger(__name__)


class StackMetadata:
    def __init__(self):
        self._core_dir = get_core_root()
        self._stacks_dir = get_stacks_root()
        self._data_dir = get_data_root()

    def list_stacks(self) -> list[str]:
        """
        List all available stacks by scanning stacks/ directory
        and including 'infra' stack from core/infra.

        :return: List of stack names
        """
        stacks = ["infra"]

        # Looks for compose.yml or docker-compose.yml in each stack directory
        if self._stacks_dir.exists():
            for stack_dir in self._stacks_dir.iterdir():
                if stack_dir.is_dir():
                    compose_yml = stack_dir / "compose.yml"
                    docker_compose_yml = stack_dir / "docker-compose.yml"
                    if compose_yml.exists() or docker_compose_yml.exists():
                        stacks.append(stack_dir.name)

        return stacks

    def stack_exists(self, stack_name: str) -> bool:
        """
        Check if a stack exists.
        :param stack_name: Name of the stack
        :return: True if stack exists, False otherwise
        """
        stack_dir = get_stack_dir(stack_name)
        compose_yml = stack_dir / "compose.yml"
        docker_compose_yml = stack_dir / "docker-compose.yml"
        return stack_dir.exists() and (compose_yml.exists() or docker_compose_yml.exists())

    def has_predeploy(self, stack_name: str) -> bool:
        """
        Check if a stack has a pre-deploy script (pre-deploy.sh or pre-deploy.py).
        :param stack_name: Name of the stack
        :return: True if pre-deploy script exists, False otherwise
        """
        if not self.stack_exists(stack_name):
            return False
        stack_dir = get_stack_dir(stack_name)
        predeploy_sh = stack_dir / "pre-deploy.sh"
        predeploy_py = stack_dir / "pre-deploy.py"
        return predeploy_sh.exists() or predeploy_py.exists()

    def _get_compose_file(self, stack_name: str) -> Path | None:
        stack_dir = get_stack_dir(stack_name)
        compose_yml = stack_dir / "compose.yml"
        docker_compose_yml = stack_dir / "docker-compose.yml"
        if compose_yml.exists():
            return compose_yml
        if docker_compose_yml.exists():
            return docker_compose_yml
        return None

    def _extract_label_value(self, labels: dict | list, label_key: str) -> str | None:
        if isinstance(labels, dict):
            return labels.get(label_key)
        if isinstance(labels, list):
            for item in labels:
                if isinstance(item, str) and "=" in item:
                    key, value = item.split("=", 1)
                    if key == label_key:
                        return value
        return None

    def _get_stack_compose_content(self, stack_name: str) -> dict:
        compose_file = self._get_compose_file(stack_name)
        if not compose_file:
            return {}

        try:
            data = yaml.safe_load(compose_file.read_text()) or {}
        except Exception:
            return {}
        return data

    def _get_stack_metadata(self, stack_name: str) -> dict:
        data = self._get_stack_compose_content(stack_name)
        metadata = data.get("x-hms")
        return metadata if isinstance(metadata, dict) else {}

    def get_description(self, stack_name: str) -> str | None:
        """
        Get description of a stack from root metadata (x-hms.description) in the compose file.
        :param stack_name: Name of the stack
        :return: Description string or empty string if not found
        """
        metadata = self._get_stack_metadata(stack_name)

        description = metadata.get("description")
        return str(description) if description is not None else None

    def list_services(self, stack_name: str) -> list[str]:
        """
        List all services defined in the stack's compose file.
        :param stack_name: Name of the stack
        :return: List of service names
        """
        compose_file = self._get_compose_file(stack_name)
        if not compose_file:
            return []

        try:
            data = yaml.safe_load(compose_file.read_text()) or {}
        except Exception:
            return []

        services = data.get("services", {})
        return list(services.keys()) if isinstance(services, dict) else []

    def _get_service_label(self, stack_name: str, service: str, label: str) -> str:
        """
        Get a single label value from a service. For multiple matches use _get_service_labels.
        :param stack_name: Name of the stack
        :param service: Name of the service
        :param label: Label key to retrieve
        :return: Label value or empty string if not found
        """
        compose = self._get_stack_compose_content(stack_name)
        services = compose.get("services", {}) or {}
        service_def = services.get(service, {}) or {}
        labels = service_def.get("labels")
        value = self._extract_label_value(labels, label)
        return str(value) if value is not None else ""

    def _get_service_labels(self, stack_name: str, service: str, label_pattern: str) -> dict[str, str]:
        """
        Get all labels matching a pattern (supports wildcards with *).
        Example: "traefik.http.routers.*.rule" matches "traefik.http.routers.tinyauth.rule"
        :param stack_name: Name of the stack
        :param service: Name of the service
        :param label_pattern: Label pattern with optional wildcards (*)
        :return: Dict of matching label keys and their values
        """
        import re

        compose = self._get_stack_compose_content(stack_name)
        services = compose.get("services", {}) or {}
        service_def = services.get(service, {}) or {}
        labels = service_def.get("labels")

        if not labels:
            return {}

        # Convert wildcard pattern to regex
        regex_pattern = "^" + re.escape(label_pattern).replace(r"\*", ".*") + "$"
        pattern = re.compile(regex_pattern)

        matches = {}

        if isinstance(labels, dict):
            for key, value in labels.items():
                if pattern.match(key):
                    matches[key] = str(value)
        elif isinstance(labels, list):
            for item in labels:
                if isinstance(item, str) and "=" in item:
                    key, value = item.split("=", 1)
                    if pattern.match(key):
                        matches[key] = value

        return matches

    def get_service_description(self, stack_name: str, service: str) -> str | None:
        """
        Get description of a service from service metadata (hms.description) in the compose file.
        :param stack_name: Name of the stack
        :param service: Name of the service
        :return: Description string or None if not found
        """
        return self._get_service_label(stack_name, service, "hms.description")

    def is_service_public(self, stack_name: str, service: str) -> bool:
        """
        Check if a service is public from traefik labels.
        :param stack_name:  Name of the stack
        :param service: Name of the service
        :return: True if service is public, False otherwise
        """
        traefik_middlewares = self._get_service_labels(stack_name, service, "traefik.http.routers.*.middlewares")

        # if any middleware contains "tinyauth" then is not public
        for label_key, middleware in traefik_middlewares.items():
            if "tinyauth@docker" in middleware.lower():
                return False
        return True and self.get_service_subdomain(stack_name, service) is not None

    def get_service_hosts(self, stack_name: str, service: str) -> list[str]:
        """
        Get hostnames from Traefik rule labels (Host(`a.example`, `b.example`)).
        :param stack_name: Name of the stack
        :param service: Name of the service
        :return: List of hostnames
        """
        import re

        traefik_rules = self._get_service_labels(stack_name, service, "traefik.http.routers.*.rule")
        hosts: list[str] = []

        for _, rule in traefik_rules.items():
            for match in re.findall(r"Host\(`([^`]+)`\)", rule):
                for host in match.split("`,`"):
                    host = host.strip()
                    if host:
                        hosts.append(host)

        # Deduplicate while preserving order
        unique_hosts = []
        for host in hosts:
            if host not in unique_hosts:
                unique_hosts.append(host)
        return unique_hosts

    def get_service_subdomain(self, stack_name: str, service: str) -> str | None:
        """
        Get subdomain of a service from traefik labels.
        "traefik.http.routers.*.rule=Host(`auth.${BASE_DOMAIN}`)"
        :param stack_name: Name of the stack
        :param service: Name of the service
        :return: Subdomain string or None if not found
        """
        traefik_rules = self._get_service_labels(stack_name, service, "traefik.http.routers.*.rule")

        for label_key, traefik_rule in traefik_rules.items():
            if "Host(`" in traefik_rule and "`)" in traefik_rule:
                host_part = traefik_rule.split("Host(`")[1].split("`)")[0]
                subdomain = host_part.split(".")[0]
                return subdomain
        return None

    def _flatten(self, d: dict, parent_key: str = '') -> dict[str, str]:
        """
        Aplana un diccionario jerárquico en un diccionario plano con claves unidas por separador.

        Ejemplo:
            {'infra': {'cloudflare': {'email': 'test@example.com'}}}
            -> {'cloudflare_email': 'test@example.com'}

        :param d: Diccionario a aplanar
        :param parent_key: Clave padre para recursión
        :return: Diccionario aplanado
        """
        items = []
        for k, v in d.items():
            new_key = f"{parent_key}_{k}" if parent_key else k
            if isinstance(v, dict):
                items.extend(self._flatten(v, new_key).items())
            if isinstance(v, list):
                items.append((new_key, ",".join(map(str, v))))
            else:
                items.append((new_key, v))
        return dict(items)

    def get_stack_vars(self, stack_name: str) -> dict[str, str]:
        """
        Obtiene variables de la configuración del stack desde config.toml.
        Combina variables globales y variables específicas del stack.
        Aplana la estructura jerárquica en variables con prefijos unidos por guiones bajos.

        :param stack_name: Nombre del stack
        :return: Diccionario con variables de entorno
        """
        from hms.lib.config import config_manager

        # 1. Variables dinámicas de HMS
        env_vars = {
            "STACK_PREFIX": f"hms-{stack_name}",
            "STACK_DATA": get_host_data_dir(stack_name),
            "STACK_DIR": get_host_stack_dir(stack_name),
            "HMS_STACK_DATA": get_data_root() / stack_name
        }

        # 2. Variables globales desde config.toml (aplanadas)
        global_config = config_manager.get_global_config()
        flattened_global = self._flatten(global_config)
        for key, value in flattened_global.items():
            env_vars[key.upper()] = str(value)

        # 3. Variables específicas del stack desde config.toml (aplanadas)
        stack_config = config_manager.get_stack_config(stack_name)
        flattened_stack = self._flatten(stack_config)
        for key, value in flattened_stack.items():
            if key != "enabled":  # Excluir la propiedad enabled
                env_vars[key.upper()] = str(value)

        logger.debug(f"Stack '{stack_name}' environment variables: {env_vars}")

        return env_vars


stack_metadata = StackMetadata()
