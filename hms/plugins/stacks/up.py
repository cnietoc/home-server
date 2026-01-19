"""Plugin: up
Deploy de un stack: genera .env, ejecuta prep y hace docker compose up -d.
"""

import subprocess
import logging
from typing import List

from hms.core.plugin import StackPlugin
from hms.lib.deploy import prep_stack, PrepError
from hms.lib.stacks import get_stack_manager

logger = logging.getLogger(__name__)


class UpPlugin(StackPlugin):
    def get_name(self) -> str:
        return "up"

    def get_description(self) -> str:
        return "Deploy: genera .env, ejecuta prep y levanta docker compose"

    def get_help(self) -> str:
        return """
up - Deploy de un stack

USO:
  hms [STACK] up [--rebuild]

COMPORTAMIENTO:
  - Verifica que el stack exista en stacks.yml y tenga docker-compose.yml
  - Genera docker/<stack>/.env
  - Ejecuta prep (pre-deploy.sh) si existe
  - docker compose up -d (opcionalmente --build con --rebuild)
"""

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        stack_manager = get_stack_manager()

        # Opciones
        rebuild = "--rebuild" in args

        try:
            prep_stack(stack_name)
        except PrepError as e:
            logger.error(f"{e}")
            return 1
        except Exception as e:
            logger.error(f"Error en prep: {e}")
            return 1

        stack_dir = stack_manager.get_stack_docker_dir(stack_name)

        # docker compose up -d
        cmd = ["docker", "compose", "up", "-d"]
        if rebuild:
            cmd.insert(3, "--build")

        try:
            logger.info(f"🚀 Levantando stack {stack_name}...")
            result = subprocess.run(cmd, cwd=str(stack_dir), check=False, text=True)
            if result.returncode != 0:
                logger.error(f"docker compose up falló con código {result.returncode}")
                return result.returncode
            logger.info(f"✅ Stack {stack_name} levantado")
            return 0
        except FileNotFoundError:
            logger.error("docker compose no encontrado")
            return 1
        except Exception as e:
            logger.error(f"Error ejecutando docker compose: {e}")
            return 1

