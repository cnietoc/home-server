"""
Módulo para interactuar con Docker Compose.
Gestión de ciclo de vida de stacks.
"""

import json
import logging
import os
import pty
import subprocess
from pathlib import Path
from typing import Optional, Dict, Tuple

from hms.lib.paths import get_stack_dir
from hms.lib.stacks import stack_metadata

logger = logging.getLogger(__name__)


class DockerComposeManager:
    """Gestor de operaciones Docker Compose."""

    def _format_docker_error(self, stderr: str) -> None:
        """
        Formatea y muestra los errores de Docker Compose de forma legible.

        :param stderr: Salida de error de docker compose
        """
        if not stderr:
            return

        lines = stderr.strip().split('\n')

        # Agrupar warnings y errores
        warnings = []
        errors = []
        other = []

        for line in lines:
            line = line.strip()
            if not line:
                continue

            # Detectar warnings de variables no definidas
            if 'WARN' in line and 'variable is not set' in line:
                # Extraer el nombre de la variable
                if 'The "' in line:
                    try:
                        # Formato: msg="The \"VARIABLE_NAME\" variable is not set..."
                        parts = line.split('The ')
                        if len(parts) > 1:
                            var_part = parts[1]
                            # Buscar hasta " variable
                            if '" variable' in var_part or '\\" variable' in var_part:
                                var_name = var_part.split('" variable')[0].strip('"\\')
                                warnings.append(var_name)
                            else:
                                other.append(line)
                        else:
                            other.append(line)
                    except (IndexError, AttributeError):
                        # Si falla el parsing, agregar la línea completa
                        other.append(line)
                else:
                    other.append(line)

        # Mostrar warnings agrupados
        if warnings:
            logger.warning(f"⚠️  Missing environment variables ({len(warnings)}):")
            for var in warnings[:5]:  # Mostrar solo las primeras 5
                logger.warning(f"   - {var}")
            if len(warnings) > 5:
                logger.warning(f"   ... and {len(warnings) - 5} more")

        # Mostrar errores críticos
        if errors:
            logger.error("❌ Critical errors:")
            for error in errors:
                # Limpiar el error de timestamps
                clean_error = error
                if 'time=' in clean_error:
                    clean_error = ' '.join([part for part in clean_error.split() if not part.startswith('time=')])
                logger.error(f"   {clean_error}")

        # Mostrar otras líneas importantes
        if other:
            for line in other:
                logger.error(f"   {line}")

    def _run_predeploy(self, stack_name: str, stack_dir: Path, env: Dict[str, str]) -> int:
        """
        Ejecuta el script pre-deploy si existe (pre-deploy.sh o pre-deploy.py).

        :param stack_name: Nombre del stack
        :param stack_dir: Directorio del stack
        :param env: Variables de entorno
        :return: Código de retorno (0 = éxito o no existe script)
        """
        predeploy_sh = stack_dir / "pre-deploy.sh"
        predeploy_py = stack_dir / "pre-deploy.py"

        script_to_run = None
        command = []

        if predeploy_sh.exists():
            script_to_run = predeploy_sh
            command = ["bash", str(predeploy_sh)]
            logger.info(f"🔧 Running pre-deploy.sh for stack '{stack_name}'...")
        elif predeploy_py.exists():
            script_to_run = predeploy_py
            command = ["python", str(predeploy_py)]
            logger.info(f"🔧 Running pre-deploy.py for stack '{stack_name}'...")

        if not script_to_run:
            logger.debug(f"No pre-deploy script found for stack '{stack_name}'")
            return 0  # No hay script, continuar normalmente

        try:
            result = subprocess.run(
                command,
                cwd=stack_dir,
                env=env,
                capture_output=True,
                text=True,
                timeout=120  # 2 minutos timeout para pre-deploy
            )

            if result.returncode == 0:
                logger.debug(f"Pre-deploy script completed successfully")
                if result.stdout:
                    # Mostrar stdout del script
                    for line in result.stdout.strip().split('\n'):
                        if line.strip():
                            logger.info(f"   {line}")
            else:
                logger.error(f"Pre-deploy script failed with code {result.returncode}")
                if result.stderr:
                    logger.error(f"Error output:")
                    for line in result.stderr.strip().split('\n'):
                        if line.strip():
                            logger.error(f"   {line}")

            return result.returncode

        except subprocess.TimeoutExpired:
            logger.error(f"Pre-deploy script timeout for stack '{stack_name}'")
            return 1
        except Exception as e:
            logger.error(f"Error running pre-deploy script for stack '{stack_name}': {e}")
            return 1

    def _get_compose_file(self, stack_name: str) -> Optional[Path]:
        """
        Encuentra el archivo compose.yml o docker-compose.yml.

        :param stack_name: Nombre del stack
        :return: Path al archivo compose o None
        """
        stack_dir = get_stack_dir(stack_name)

        compose_yml = stack_dir / "compose.yml"
        if compose_yml.exists():
            return compose_yml

        docker_compose_yml = stack_dir / "docker-compose.yml"
        if docker_compose_yml.exists():
            return docker_compose_yml

        return None

    def get_stack_status(self, stack_name: str) -> str:
        """
        Obtiene el estado de un stack.

        :param stack_name: Nombre del stack
        :return: 'running', 'stopped', 'partial', 'not-found'
        """
        compose_file = self._get_compose_file(stack_name)

        if not compose_file:
            logger.debug(f"No compose file found for stack '{stack_name}'")
            return "not-found"

        try:
            result, output = self._exec(
                ["docker", "compose", "ps", "--format", "json"],
                stack_name,
                hidden=True
            )

            # Parsear salida JSON
            if not output:
                return "stopped"

            # Puede ser una lista de objetos JSON, uno por línea
            containers = []
            for line in output.split('\n'):
                if line.strip():
                    try:
                        containers.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue

            if not containers:
                return "stopped"

            # Verificar estados
            running_count = sum(1 for c in containers if c.get("State") == "running")
            total_count = len(containers)

            if running_count == 0:
                return "stopped"
            elif running_count == total_count:
                return "running"
            else:
                return "partial"

        except subprocess.TimeoutExpired:
            logger.error(f"Timeout checking status for stack '{stack_name}'")
            return "not-found"
        except Exception as e:
            logger.error(f"Error checking status for stack '{stack_name}': {e}")
            return "not-found"

    def _exec(self, command: list, stack_name: str, env: Optional[dict] = None, hidden: bool = False) -> Tuple[int, str]:
        """
        Ejecuta un comando docker compose en el directorio del stack.

        :param command: Comando como lista
        :param stack_name: Nombre del stack
        :param env: Variables de entorno
        :param hidden: Si es True, no muestra la salida por consola
        :return: Salida estándar del comando
        """
        stack_dir = get_stack_dir(stack_name)

        master, slave = pty.openpty()
        output_buffer = []
        try:
            process = subprocess.Popen(
                command,
                cwd=stack_dir,
                stdin=slave,
                env=env,
                stdout=slave,
                stderr=slave,
                close_fds=True
            )

            os.close(slave)

            while True:
                try:
                    output = os.read(master, 1024)
                    if not output:
                        break
                    if not hidden:
                        os.write(1, output)  # stdout real solo si no está oculto
                    output_buffer.append(output)
                except OSError:
                    break

            process.wait()
        except subprocess.TimeoutExpired:
            logger.error(f"Timeout executing command {' '.join(command)} for stack '{stack_name}'")
            return 1, b"".join(output_buffer).decode(errors="replace")
        except Exception as e:
            logger.error(f"Error executing command {' '.join(command)} for stack '{stack_name}': {e}")
            return 1, b"".join(output_buffer).decode(errors="replace")

        return process.returncode, b"".join(output_buffer).decode(errors="replace")

    def stack_up(self, stack_name: str) -> int:
        """
        Levanta un stack con docker compose up -d.
        Detecta cambios automáticamente y solo recrea lo necesario.

        :param stack_name: Nombre del stack
        :param env_vars: Variables de entorno adicionales
        :return: Código de retorno (0 = éxito)
        """
        stack_dir = get_stack_dir(stack_name)
        compose_file = self._get_compose_file(stack_name)

        if not compose_file:
            logger.error(f"No compose file found for stack '{stack_name}'")
            return 1

        try:
            # Preparar entorno
            import os
            env = os.environ.copy()
            env_vars = stack_metadata.get_stack_vars(stack_name)
            if env_vars:
                env.update(env_vars)

            # Ejecutar pre-deploy script si existe
            predeploy_result = self._run_predeploy(stack_name, stack_dir, env)
            if predeploy_result != 0:
                logger.error(f"Pre-deploy script failed for stack '{stack_name}'")
                return predeploy_result

            # Ejecutar docker compose up -d con salida en tiempo real
            logger.debug(f"Running: docker compose up -d in {stack_dir}")

            result, output = self._exec(
                ["docker", "compose", "up", "-d", "--build"],
                stack_name,
                env
            )

            self._format_docker_error(output)

            return result

        except Exception as e:
            logger.error(f"Error bringing up stack '{stack_name}': {e}")
            return 1

    def stack_down(self, stack_name: str) -> int:
        """
        Para un stack con docker compose down.

        :param stack_name: Nombre del stack
        :return: Código de retorno (0 = éxito)
        """
        stack_dir = get_stack_dir(stack_name)
        compose_file = self._get_compose_file(stack_name)
        if not compose_file:
            logger.error(f"No compose file found for stack '{stack_name}'")
            return 1

        try:
            # Ejecutar docker compose down con salida en tiempo real
            logger.debug(f"Running: docker compose down in {stack_dir}")

            env = os.environ.copy()
            env_vars = stack_metadata.get_stack_vars(stack_name)
            if env_vars:
                env.update(env_vars)

            result, output = self._exec(
                ["docker", "compose", "down", "--remove-orphans"],
                stack_name,
                env=env,
                hidden=True
            )

            self._format_docker_error(output)

            return result

        except Exception as e:
            logger.error(f"Error bringing down stack '{stack_name}': {e}")
            return 1


docker_manager = DockerComposeManager()
