"""Configuración y generación de .env por stack.

Actualmente lee desde `config/private/*.env` en el host y genera
`docker/<stack>/.env`. Diseñado para sustituir fácilmente la fuente
por OneDrive en el futuro.
"""

from pathlib import Path
from typing import List
import os
import subprocess

from hms.lib.paths import get_config_root, get_docker_root
from hms.lib.stacks import get_stack_manager


class EnvGenerator:
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

    def generate_stack_env(self, stack_name: str) -> Path:
        """Genera docker/<stack>/.env combinando common.env y los envs declarados en stacks.yml.
        Retorna la ruta del archivo generado.
        """
        info = self._stack_manager.get_stack_info(stack_name)
        # Si el stack no existe en stacks.yml, fallamos explícitamente
        if not self._stack_manager.stack_exists(stack_name):
            raise ValueError(f"Stack '{stack_name}' no definido en stacks.yml")

        stack_dir = get_docker_root() / stack_name
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


def get_env_generator(project_root: Path | None = None) -> EnvGenerator:
    return EnvGenerator(project_root)
