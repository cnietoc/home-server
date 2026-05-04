"""
hms.lib.host_runner — runs CLI commands in an ephemeral container cloned
from the HMS daemon but with network_mode=host.

Useful for operations that need to see the LAN as a host process:
- UPnP IGD (router rejects requests from Docker bridge IPs)
- mDNS / SSDP / any multicast-based discovery
- Ping/traceroute to LAN devices
"""

import json
import logging
import os
import subprocess

logger = logging.getLogger(__name__)

DAEMON_CONTAINER = "hms"
HOST_RUNNER_ENV = "HMS_HOST_RUNNER"


class HostRunnerError(Exception):
    pass


def is_host_runner() -> bool:
    """True if this process is already running inside a host-mode ephemeral container."""
    return bool(os.environ.get(HOST_RUNNER_ENV))


def run_hms_in_host_network(cli_args: list[str]) -> int:
    """
    Lanza `python -m hms <cli_args>` en un contenedor efímero clonado del daemon
    pero con --network=host. Devuelve el exit code. Streamea stdout/stderr al
    proceso llamante.

    Mismo primitivo para todos los call-sites:

      # Desde un helper (siempre spawn, sin guard):
      run_hms_in_host_network(["system", "refresh-port-forwards", "--stack", "terraria"])

      # Desde el plugin (con guard anti-recursión):
      def run(self, args):
          if not is_host_runner():
              return run_hms_in_host_network(["system", "refresh-port-forwards", *args])
          # ...trabajo in-process garantizado en host network...
    """
    try:
        raw = subprocess.run(
            ["docker", "inspect", DAEMON_CONTAINER],
            capture_output=True, text=True, check=True,
        ).stdout
    except subprocess.CalledProcessError as e:
        raise HostRunnerError(
            f"Could not inspect container '{DAEMON_CONTAINER}': {e.stderr.strip()}"
        ) from e

    info = json.loads(raw)[0]
    image = info["Image"]  # sha256:... exacto del daemon vivo — sin riesgo de version-skew
    user = info["Config"].get("User", "")
    group_add = info["HostConfig"].get("GroupAdd") or []

    volume_args: list[str] = []
    for m in info["Mounts"]:
        if m["Type"] == "bind":
            volume_args += ["-v", f"{m['Source']}:{m['Destination']}"]

    cmd_label = cli_args[1] if len(cli_args) > 1 else cli_args[0] if cli_args else "host"
    name = f"hms-{cmd_label}-{os.urandom(2).hex()}"
    cmd = [
        "docker", "run", "--rm", "--network=host",
        "--name", name,
        *(["--user", user] if user else []),
        *[arg for g in group_add for arg in ("--group-add", str(g))],
        *volume_args,
        "-e", f"{HOST_RUNNER_ENV}=1",
        "-e", "HMS_LOG_TAG=host",
        image,
        "python", "-m", "hms", *cli_args,
    ]
    logger.debug("host-runner spawn: %s", " ".join(cmd))
    return subprocess.run(cmd).returncode
