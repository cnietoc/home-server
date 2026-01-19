"""Plugin: prep
Ejecuta el pre-deploy de un stack (si existe) y genera .env antes.
"""

from typing import List

from hms.core.plugin import StackPlugin
from hms.lib.deploy import prep_stack, PrepError


class PrepPlugin(StackPlugin):
    def get_name(self) -> str:
        return "prep"

    def get_description(self) -> str:
        return "Ejecuta pre-deploy.sh y genera .env para el stack"

    def get_help(self) -> str:
        return """
prep - Ejecuta el pre-deploy de un stack

USO:
  hms [STACK] prep

COMPORTAMIENTO:
  - Verifica que el stack exista en stacks.yml y tenga docker-compose.yml
  - Genera docker/<stack>/.env combinando common.env y config_files declarados
  - Ejecuta docker/<stack>/pre-deploy.sh si existe
"""

    def run_for_stack(self, stack_name: str, args: List[str]) -> int:
        try:
            prep_stack(stack_name)
            return 0
        except PrepError as e:
            print(f"❌ {e}")
            return 1
        except Exception as e:
            print(f"❌ Error: {e}")
            return 1

