"""
Plugin: system logs
Ver logs de HMS (daemon y CLI) en tiempo real o snapshot.
"""

import logging
import subprocess
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib.paths import get_logs_root

logger = logging.getLogger(__name__)

LOG_FILE = "hms.log"


class LogsPlugin(GlobalPlugin):
    """Ver logs del daemon/CLI de HMS."""

    def get_name(self) -> str:
        return "logs"

    def get_description(self) -> str:
        return "Ver logs de HMS"

    def get_help(self) -> str:
        return f"""
logs - Ver logs de HMS

USAGE:
  hms system logs [OPTIONS]

DESCRIPTION:
  Muestra el contenido de {LOG_FILE} (logs unificados de daemon y CLI).
  Usa --grep para filtrar por patrón, o filtra por origen con:
    --grep "\\[daemon\\]"   → solo logs del daemon
    --grep "\\[cli\\]"      → solo logs del CLI

OPTIONS:
  -n, --lines N       Número de líneas a mostrar (por defecto: 50)
  -f, --follow        Seguir en tiempo real (como tail -f)
  --grep PATTERN      Filtrar líneas por patrón (regex)
  -h, --help          Mostrar esta ayuda

EXAMPLES:
  hms system logs                          # Últimas 50 líneas
  hms system logs -n 200                   # Últimas 200 líneas
  hms system logs -f                       # Follow en tiempo real
  hms system logs -f --grep "ERROR"        # Follow solo errores
  hms system logs -f --grep "\\[cli\\]"    # Follow solo CLI
  hms system logs --grep "backup"          # Buscar menciones de backup
"""

    def run(self, args: List[str]) -> int:
        lines = 50
        follow = False
        grep_pattern = None

        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("-h", "--help"):
                print(self.get_help())
                return 0
            elif arg in ("-n", "--lines"):
                if i + 1 >= len(args):
                    logger.error("--lines requiere un valor numérico")
                    return 1
                try:
                    lines = int(args[i + 1])
                except ValueError:
                    logger.error(f"--lines: valor inválido '{args[i + 1]}'")
                    return 1
                i += 2
            elif arg in ("-f", "--follow"):
                follow = True
                i += 1
            elif arg == "--grep":
                if i + 1 >= len(args):
                    logger.error("--grep requiere un patrón")
                    return 1
                grep_pattern = args[i + 1]
                i += 2
            else:
                logger.error(f"Argumento desconocido: {arg}")
                return 1

        log_path = get_logs_root() / LOG_FILE
        if not log_path.exists():
            logger.error(f"No hay logs todavía: {log_path}")
            return 1

        tail_cmd = ["tail", f"-n{lines}"]
        if follow:
            tail_cmd.append("-f")
        tail_cmd.append(str(log_path))

        if grep_pattern:
            tail = subprocess.Popen(tail_cmd, stdout=subprocess.PIPE)
            grep = subprocess.run(
                ["grep", "--line-buffered", "-E", grep_pattern],
                stdin=tail.stdout,
            )
            tail.wait()
            return grep.returncode

        return subprocess.call(tail_cmd)
