"""Plugin: down
Detiene un stack usando docker compose down.
"""

import subprocess
from typing import List

from hms.core.plugin import StackPlugin
from hms.lib.stacks import get_stack_manager


class DownPlugin(StackPlugin):
    def get_name(self) -> str:
        return "down"

    def get_description(self) -> str:
        return "Detiene un stack (docker compose down)"

    def get_help(self) -> str:
        return """
down - Detiene un stack

USO:
  hms [STACK] down [--volumes] [--images] [--networks]

COMPORTAMIENTO:
  - Verifica que el stack exista en stacks.yml y tenga docker-compose.yml
  - Ejecuta docker compose down con flags opcionales
"""

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        stack_manager = get_stack_manager()

        if not stack_manager.stack_exists(stack_name):
            print(f"❌ Stack '{stack_name}' no definido en stacks.yml")
            return 1

        info = stack_manager.get_stack_info(stack_name)
        if not info.get("has_compose"):
            print(f"❌ Stack '{stack_name}' no tiene docker-compose.yml")
            return 1

        stack_dir = stack_manager.get_stack_docker_dir(stack_name)

        # Flags
        volumes = "--volumes" in args
        images = "--images" in args
        networks = "--networks" in args

        cmd = ["docker", "compose", "down"]
        if volumes:
            cmd.append("--volumes")
        if images:
            cmd.append("--rmi")
            cmd.append("all")
        if networks:
            cmd.append("--remove-orphans")

        try:
            print(f"🛑 Parando stack {stack_name}...")
            result = subprocess.run(cmd, cwd=str(stack_dir), check=False, text=True)
            if result.returncode != 0:
                print(f"❌ docker compose down falló con código {result.returncode}")
                return result.returncode
            print(f"✅ Stack {stack_name} detenido")
            return 0
        except FileNotFoundError:
            print("❌ docker compose no encontrado")
            return 1
        except Exception as e:
            print(f"❌ Error ejecutando docker compose: {e}")
            return 1

