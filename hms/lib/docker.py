"""
Module for interacting with Docker Compose.
Stack lifecycle management.
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
    """Docker Compose operations manager."""

    def _format_docker_error(self, stderr: str) -> None:
        """
        Formats and displays Docker Compose errors in a readable way.

        :param stderr: Error output from docker compose
        """
        if not stderr:
            return

        lines = stderr.strip().split('\n')

        # Group warnings and errors
        warnings = []
        errors = []
        other = []

        for line in lines:
            line = line.strip()
            if not line:
                continue

            # Detect warnings about undefined variables
            if 'WARN' in line and 'variable is not set' in line:
                # Extract the variable name
                if 'The "' in line:
                    try:
                        # Format: msg="The \"VARIABLE_NAME\" variable is not set..."
                        parts = line.split('The ')
                        if len(parts) > 1:
                            var_part = parts[1]
                            # Look for " variable
                            if '" variable' in var_part or '\\" variable' in var_part:
                                var_name = var_part.split('" variable')[0].strip('"\\')
                                warnings.append(var_name)
                            else:
                                other.append(line)
                        else:
                            other.append(line)
                    except (IndexError, AttributeError):
                        # If parsing fails, add the full line
                        other.append(line)
                else:
                    other.append(line)

        # Display grouped warnings
        if warnings:
            logger.warning(f"⚠️  Missing environment variables ({len(warnings)}):")
            for var in warnings[:5]:  # Show only the first 5
                logger.warning(f"   - {var}")
            if len(warnings) > 5:
                logger.warning(f"   ... and {len(warnings) - 5} more")

        # Display critical errors
        if errors:
            logger.error("❌ Critical errors:")
            for error in errors:
                # Strip timestamps from the error
                clean_error = error
                if 'time=' in clean_error:
                    clean_error = ' '.join([part for part in clean_error.split() if not part.startswith('time=')])
                logger.error(f"   {clean_error}")

        # Display other important lines
        if other:
            for line in other:
                logger.error(f"   {line}")

    def _run_predeploy(self, stack_name: str, stack_dir: Path, env: Dict[str, str]) -> int:
        """
        Runs the pre-deploy script if it exists (pre-deploy.sh or pre-deploy.py).

        :param stack_name: Stack name
        :param stack_dir: Stack directory
        :param env: Environment variables
        :return: Return code (0 = success or no script found)
        """
        predeploy_sh = stack_dir / "pre-deploy.sh"
        predeploy_py = stack_dir / "pre-deploy.py"

        script_to_run = None
        command = []

        if predeploy_sh.exists():
            script_to_run = predeploy_sh
            command = ["bash", str(predeploy_sh)]
            from hms.lib import ui as _ui
            _ui.info(f"🔧 Running pre-deploy.sh for stack '{stack_name}'...")
        elif predeploy_py.exists():
            script_to_run = predeploy_py
            command = ["python", str(predeploy_py)]
            from hms.lib import ui as _ui
            _ui.info(f"🔧 Running pre-deploy.py for stack '{stack_name}'...")

        if not script_to_run:
            logger.debug(f"No pre-deploy script found for stack '{stack_name}'")
            return 0  # No script, continue normally

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
                    # Display stdout from the script
                    for line in result.stdout.strip().split('\n'):
                        if line.strip():
                            logger.info(f"   {line}")
            else:
                from hms.lib import ui as _ui
                _ui.err(f"Pre-deploy script failed for '{stack_name}' (exit {result.returncode})")
                logger.error("pre-deploy failed for '%s' (exit %d)", stack_name, result.returncode)
                if result.stderr:
                    for line in result.stderr.strip().split('\n'):
                        if line.strip():
                            logger.error("   %s", line)

            return result.returncode

        except subprocess.TimeoutExpired:
            from hms.lib import ui as _ui
            _ui.err(f"Pre-deploy script timed out for '{stack_name}'")
            logger.error("pre-deploy timeout for '%s'", stack_name)
            return 1
        except Exception:
            logger.exception("pre-deploy error for '%s'", stack_name)
            return 1

    def _get_compose_file(self, stack_name: str) -> Optional[Path]:
        """
        Finds the compose.yml or docker-compose.yml file.

        :param stack_name: Stack name
        :return: Path to the compose file or None
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
        Returns the status of a stack.

        :param stack_name: Stack name
        :return: 'running', 'stopped', 'partial', 'not-found'
        """
        compose_file = self._get_compose_file(stack_name)

        if not compose_file:
            logger.debug(f"No compose file found for stack '{stack_name}'")
            return "not-found"

        try:
            import os
            env = os.environ.copy()
            env_vars = stack_metadata.get_stack_vars(stack_name)
            if env_vars:
                env.update(env_vars)

            result, output = self._exec(
                ["docker", "compose", "ps", "--format", "json"],
                stack_name,
                env,
                hidden=True
            )

            # Parse JSON output
            if not output:
                return "stopped"

            # May be a list of JSON objects, one per line
            containers = []
            for line in output.split('\n'):
                if line.strip():
                    try:
                        containers.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue

            if not containers:
                return "stopped"

            # Check states
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
        except Exception:
            logger.exception(f"Error checking status for stack '{stack_name}'")
            return "not-found"

    def _get_stack_containers(self, stack_name: str) -> list[dict]:
        """
        Returns the list of containers for a stack.

        :param stack_name: Stack name
        :return: List of dictionaries with container information
        """
        compose_file = self._get_compose_file(stack_name)
        if not compose_file:
            return []

        try:
            env = os.environ.copy()
            env_vars = stack_metadata.get_stack_vars(stack_name)
            if env_vars:
                env.update(env_vars)

            _, output = self._exec(
                ["docker", "compose", "ps", "--format", "json"],
                stack_name,
                env,
                hidden=True,
            )

            containers: list[dict] = []
            for line in output.split("\n"):
                if line.strip():
                    try:
                        containers.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
            return containers
        except Exception as e:
            logger.error(f"Error listing containers for stack '{stack_name}': {e}")
            return []

    def get_stack_container_counts(self, stack_name: str) -> dict:
        """
        Returns the container count by state for a stack.

        :param stack_name: Stack name
        :return: Dictionary with counts of running, stopped, and total containers
        """
        containers = self._get_stack_containers(stack_name)
        if not containers:
            return {"running": 0, "stopped": 0, "total": 0}

        running = sum(1 for c in containers if c.get("State") == "running")
        total = len(containers)
        return {"running": running, "stopped": max(total - running, 0), "total": total}

    def get_stack_service_counts(self, stack_name: str) -> dict[str, dict]:
        """
        Returns the container count per service for a stack.

        :param stack_name: Stack name
        :return: Dictionary with container counts per service
        """
        containers = self._get_stack_containers(stack_name)
        if not containers:
            return {}

        services: dict[str, dict] = {}
        for container in containers:
            service = container.get("Service") or container.get("service")
            if not service:
                continue
            state = container.get("State") or container.get("state")
            if service not in services:
                services[service] = {"running": 0, "stopped": 0, "total": 0}
            services[service]["total"] += 1
            if state == "running":
                services[service]["running"] += 1

        for service, counts in services.items():
            counts["stopped"] = max(counts["total"] - counts["running"], 0)
            if counts["running"] == 0:
                counts["state"] = "stopped"
            elif counts["running"] == counts["total"]:
                counts["state"] = "running"
            else:
                counts["state"] = "partial"

        return services

    def _exec(self, command: list, stack_name: str, env: Optional[dict], hidden: bool = False) -> Tuple[int, str]:
        """
        Executes a docker compose command in the stack directory.

        :param command: Command as a list
        :param stack_name: Stack name
        :param env: Environment variables
        :param hidden: If True, do not print output to the console
        :return: Standard output of the command
        """
        stack_dir = get_stack_dir(stack_name)

        master, slave = pty.openpty()
        output_buffer = []
        try:
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
            finally:
                os.close(slave)

            try:
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

                process.wait(timeout=300)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                logger.error(f"Timeout executing command {' '.join(command)} for stack '{stack_name}'")
                return 1, b"".join(output_buffer).decode(errors="replace")
            except Exception:
                logger.exception(f"Error executing command {' '.join(command)} for stack '{stack_name}'")
                return 1, b"".join(output_buffer).decode(errors="replace")
        finally:
            os.close(master)

        return process.returncode, b"".join(output_buffer).decode(errors="replace")

    def stack_up(self, stack_name: str) -> int:
        """
        Starts a stack with docker compose up -d.
        Automatically detects changes and only recreates what is necessary.

        :param stack_name: Stack name
        :return: Return code (0 = success)
        """
        stack_dir = get_stack_dir(stack_name)
        compose_file = self._get_compose_file(stack_name)

        if not compose_file:
            logger.error(f"No compose file found for stack '{stack_name}'")
            return 1

        try:
            # Prepare environment
            import os
            env = os.environ.copy()
            env_vars = stack_metadata.get_stack_vars(stack_name)
            if env_vars:
                env.update(env_vars)

            # Run pre-deploy script if it exists
            predeploy_result = self._run_predeploy(stack_name, stack_dir, env)
            if predeploy_result != 0:
                logger.error(f"Pre-deploy script failed for stack '{stack_name}'")
                return predeploy_result

            # Run docker compose up -d with real-time output
            logger.debug(f"Running: docker compose up -d in {stack_dir}")

            result, output = self._exec(
                ["docker", "compose", "up", "-d", "--build"],
                stack_name,
                env
            )

            self._format_docker_error(output)

            return result

        except Exception:
            logger.exception(f"Error bringing up stack '{stack_name}'")
            return 1

    def stack_down(self, stack_name: str) -> int:
        """
        Stops a stack with docker compose down.

        :param stack_name: Stack name
        :return: Return code (0 = success)
        """
        stack_dir = get_stack_dir(stack_name)
        compose_file = self._get_compose_file(stack_name)
        if not compose_file:
            logger.error(f"No compose file found for stack '{stack_name}'")
            return 1

        try:
            # Run docker compose down with real-time output
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

    def _get_stack_image_ids(self, stack_name: str, env: dict) -> dict:
        """Returns {image: id} for images defined in the stack's compose file."""
        _, images_output = self._exec(
            ["docker", "compose", "config", "--images"],
            stack_name,
            env,
            hidden=True
        )
        ids = {}
        for image in (line.strip() for line in images_output.splitlines() if line.strip()):
            _, inspect_output = self._exec(
                ["docker", "image", "inspect", "--format", "{{.Id}}", image],
                stack_name,
                env,
                hidden=True
            )
            ids[image] = inspect_output.strip()
        return ids

    def stack_pull(self, stack_name: str) -> tuple[int, bool]:
        """
        Pulls the latest images for a stack with docker compose pull.

        :param stack_name: Stack name
        :return: (exit_code, has_updates) — has_updates is True if any new image was downloaded
        """
        compose_file = self._get_compose_file(stack_name)
        if not compose_file:
            logger.error(f"No compose file found for stack '{stack_name}'")
            return 1, False

        try:
            env = os.environ.copy()
            env_vars = stack_metadata.get_stack_vars(stack_name)
            if env_vars:
                env.update(env_vars)

            ids_before = self._get_stack_image_ids(stack_name, env)

            result, output = self._exec(
                ["docker", "compose", "pull"],
                stack_name,
                env
            )

            self._format_docker_error(output)

            ids_after = self._get_stack_image_ids(stack_name, env)
            has_updates = ids_before != ids_after
            return result, has_updates

        except Exception as e:
            logger.error(f"Error pulling images for stack '{stack_name}': {e}")
            return 1, False

    def stack_logs(self, stack_name: str, args: list = None) -> int:
        """
        Shows logs for a stack using docker compose logs.
        Supports passing all docker compose logs arguments.

        :param stack_name: Stack name
        :param args: Additional arguments for docker compose logs (e.g. ['-f', '--tail=100'])
        :return: Return code (0 = success)
        """
        if args is None:
            args = []

        stack_dir = get_stack_dir(stack_name)
        compose_file = self._get_compose_file(stack_name)

        if not compose_file:
            logger.error(f"No compose file found for stack '{stack_name}'")
            return 1

        try:
            # Prepare environment
            env = os.environ.copy()
            env_vars = stack_metadata.get_stack_vars(stack_name)
            if env_vars:
                env.update(env_vars)

            # Build command: docker compose logs [args]
            command = ["docker", "compose", "logs"] + args

            logger.debug(f"Running: {' '.join(command)} in {stack_dir}")

            result, output = self._exec(
                command,
                stack_name,
                env=env,
                hidden=False
            )

            return result

        except Exception as e:
            logger.error(f"Error retrieving logs for stack '{stack_name}': {e}")
            return 1


    def wait_for_healthy(self, stack_name: str, timeout: int = 120, poll_interval: float = 3.0) -> bool:
        """
        Wait until all containers with healthchecks are healthy.
        Returns True if healthy (or no healthchecks defined), False on timeout or unhealthy.
        """
        import time

        deadline = time.time() + timeout
        while time.time() < deadline:
            containers = self._get_stack_containers(stack_name)
            if not containers:
                return False

            with_health = [c for c in containers if c.get("Health") not in ("", None)]
            if not with_health:
                return True

            if any(c.get("Health") == "unhealthy" for c in with_health):
                return False

            if all(c.get("Health") == "healthy" for c in with_health):
                return True

            time.sleep(poll_interval)

        return False


docker_manager = DockerComposeManager()
