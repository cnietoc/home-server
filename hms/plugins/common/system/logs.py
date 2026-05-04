"""
Plugin: system logs
View HMS logs (daemon and CLI) in real time or as a snapshot.
"""

import subprocess
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib import ui
from hms.lib.paths import get_logs_root

LOG_FILE = "hms.log"


class LogsPlugin(GlobalPlugin):
    """View HMS daemon/CLI logs."""

    def get_name(self) -> str:
        return "logs"

    def get_description(self) -> str:
        return "View HMS logs"

    def get_help(self) -> str:
        return f"""
logs - View HMS logs

USAGE:
  hms system logs [OPTIONS]

DESCRIPTION:
  Displays the contents of {LOG_FILE} (unified daemon and CLI logs).
  Use --grep to filter by pattern, or filter by source with:
    --grep "\\[daemon\\]"   → daemon logs only
    --grep "\\[cli\\]"      → CLI logs only

OPTIONS:
  -n, --lines N       Number of lines to show (default: 50)
  -f, --follow        Follow in real time (like tail -f)
  --grep PATTERN      Filter lines by pattern (regex)
  -h, --help          Show this help

EXAMPLES:
  hms system logs                          # Last 50 lines
  hms system logs -n 200                   # Last 200 lines
  hms system logs -f                       # Follow in real time
  hms system logs -f --grep "ERROR"        # Follow errors only
  hms system logs -f --grep "\\[cli\\]"    # Follow CLI only
  hms system logs --grep "backup"          # Search for backup mentions
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
                    ui.err("--lines requires a numeric value")
                    return 1
                try:
                    lines = int(args[i + 1])
                except ValueError:
                    ui.err(f"--lines: invalid value '{args[i + 1]}'")
                    return 1
                i += 2
            elif arg in ("-f", "--follow"):
                follow = True
                i += 1
            elif arg == "--grep":
                if i + 1 >= len(args):
                    ui.err("--grep requires a pattern")
                    return 1
                grep_pattern = args[i + 1]
                i += 2
            else:
                ui.err(f"Unknown argument: {arg}")
                return 1

        log_path = get_logs_root() / LOG_FILE
        if not log_path.exists():
            ui.err(f"No logs yet: {log_path}")
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
