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
    Launches `python -m hms <cli_args>` in an ephemeral container cloned from the
    daemon but with --network=host. Returns the exit code. Streams stdout/stderr to
    the calling process.

    Same primitive for all call-sites:

      # From a helper (always spawn, no guard):
      run_hms_in_host_network(["system", "refresh-port-forwards", "--stack", "terraria"])

      # From the plugin (with anti-recursion guard):
      def run(self, args):
          if not is_host_runner():
              return run_hms_in_host_network(["system", "refresh-port-forwards", *args])
          # ...in-process work guaranteed on host network...
    """
    try:
        raw = subprocess.run(
            ["docker", "inspect", DAEMON_CONTAINER],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    except subprocess.CalledProcessError as e:
        raise HostRunnerError(
            f"Could not inspect container '{DAEMON_CONTAINER}': {e.stderr.strip()}"
        ) from e

    info = json.loads(raw)[0]
    image = info["Image"]  # sha256:... exact digest from the live daemon — no version-skew risk
    user = info["Config"].get("User", "")
    group_add = info["HostConfig"].get("GroupAdd") or []

    volume_args: list[str] = []
    for m in info["Mounts"]:
        if m["Type"] == "bind":
            volume_args += ["-v", f"{m['Source']}:{m['Destination']}"]

    cmd_label = cli_args[1] if len(cli_args) > 1 else cli_args[0] if cli_args else "host"
    name = f"hms-{cmd_label}-{os.urandom(2).hex()}"
    cmd = [
        "docker",
        "run",
        "--rm",
        "--network=host",
        "--name",
        name,
        *(["--user", user] if user else []),
        *[arg for g in group_add for arg in ("--group-add", str(g))],
        *volume_args,
        "-e",
        f"{HOST_RUNNER_ENV}=1",
        "-e",
        "HMS_LOG_TAG=host",
        image,
        "python",
        "-m",
        "hms",
        *cli_args,
    ]
    logger.debug("host-runner spawn: %s", " ".join(cmd))
    return subprocess.run(cmd).returncode
