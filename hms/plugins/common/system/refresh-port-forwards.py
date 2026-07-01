"""
Plugin: system refresh-port-forwards
Refreshes port mappings on the router via UPnP IGD or NAT-PMP.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib import ui

logger = logging.getLogger(__name__)


class RefreshPortForwardsPlugin(GlobalPlugin):
    """Refresh UPnP/NAT-PMP port-forwards on the router."""

    def get_name(self) -> str:
        return "refresh-port-forwards"

    def get_description(self) -> str:
        return "Refresh UPnP/NAT-PMP port-forwards on the router"

    def get_help(self) -> str:
        return """
refresh-port-forwards - Refresh port-forwards on the router

USAGE:
  hms system refresh-port-forwards [OPTIONS]

DESCRIPTION:
  Reconciles the router's port mappings with those declared in
  x-hms.public_ports for each enabled stack. Adds missing entries and
  refreshes existing ones to renew UPnP leases.

  This command runs automatically at HMS startup and every 30 min.

OPTIONS:
  --dry-run     Only show what changes would be made, without applying them
  --list        List active mappings on the router
  --prune       Remove from the router mappings that are no longer declared
  -v, --verbose Show detailed information
  -h, --help    Show this help

CONFIGURATION:
  [global]
  host_ip = "192.168.X.X"   # Host IP (required; auto-configured by `hms install`)

  [router]
  enabled        = true
  backend        = "upnp"   # "upnp" | "natpmp" | "none"
  gateway_ip     = ""       # Router IP (empty = auto-detect)
  lease_duration = "3600"   # seconds

EXAMPLES:
  hms system refresh-port-forwards              # Reconcile
  hms system refresh-port-forwards --list       # View router state
  hms system refresh-port-forwards --dry-run    # Preview changes
  hms system refresh-port-forwards --prune      # Remove stale mappings
"""

    def run(self, args: List[str]) -> int:
        from hms.lib.host_runner import is_host_runner, run_hms_in_host_network

        if not is_host_runner():
            return run_hms_in_host_network(["system", "refresh-port-forwards", *args])

        dry_run = False
        list_only = False
        prune = False
        verbose = False
        stack_name: str | None = None
        remove = False

        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("--help", "-h"):
                print(self.get_help())
                return 0
            elif arg == "--dry-run":
                dry_run = True
            elif arg == "--list":
                list_only = True
            elif arg == "--prune":
                prune = True
            elif arg in ("-v", "--verbose"):
                verbose = True
            elif arg == "--stack":
                i += 1
                if i >= len(args):
                    ui.err("--stack requires an argument")
                    return 1
                stack_name = args[i]
            elif arg == "--remove":
                remove = True
            else:
                ui.err(f"Unknown argument: {arg}")
                return 1
            i += 1

        if stack_name:
            from hms.lib.router import _apply_ports_for_stack, _remove_ports_for_stack

            if remove:
                _remove_ports_for_stack(stack_name)
            else:
                _apply_ports_for_stack(stack_name)
            return 0

        from hms.lib.config import config_manager
        from hms.lib.router import (
            RouterError,
            get_router_client,
        )

        cfg = config_manager.get_router_config()
        if not cfg.get("enabled", True):
            ui.info("ℹ️  Port-forwarding disabled (router.enabled = false)")
            return 0

        try:
            client = get_router_client()
        except RouterError as e:
            ui.err(f"Router: {e}")
            logger.error("Router connect failed: %s", e)
            return 1
        except Exception:
            ui.err("Unexpected error connecting to router")
            logger.exception("Router connect failed")
            return 1

        if list_only:
            return self._list_mappings(client, cfg)

        return self._reconcile(client, cfg, dry_run=dry_run, prune=prune, verbose=verbose)

    def _list_mappings(self, client, cfg: dict) -> int:
        try:
            mappings = client.list_mappings()
        except Exception:
            ui.err("Could not list router mappings")
            logger.exception("list_mappings failed")
            return 1

        if not mappings:
            ui.info("ℹ️  No active mappings (or the backend does not support enumeration)")
            return 0

        try:
            ext_ip = client.get_external_ip()
            ui.info(f"🌐 Public IP: {ext_ip}")
        except Exception:
            pass

        ui.info(f"📋 Active mappings on the router ({len(mappings)}):")
        ui.info("")
        for m in mappings:
            port = m.get("ext_port", "?")
            proto = m.get("protocol", "?")
            dest = f"{m.get('int_client', '?')}:{m.get('int_port', '?')}"
            desc = m.get("description", "")
            lease = m.get("lease_time", 0)
            lease_str = f"lease: {lease}s" if lease else "lease: permanente"
            ui.info(f"  {port:<6}/{proto:<4} → {dest:<22} {desc!r:<35} ({lease_str})")

        ui.info("")
        return 0

    def _reconcile(self, client, cfg: dict, dry_run: bool, prune: bool, verbose: bool) -> int:
        from hms.lib.config import config_manager
        from hms.lib.router import get_desired_mappings, reconcile_port_forwards

        exclude = cfg.get("exclude_stacks", [])
        desired = get_desired_mappings(exclude_stacks=exclude)

        if not desired:
            ui.info("ℹ️  No stack has public_ports declared")
            return 0

        lan_ip = config_manager.get_global_config().get("host_ip", "")
        if not lan_ip:
            ui.err("global.host_ip is not configured. Run `hms install` or add it to config.toml.")
            return 1
        lease = int(cfg.get("lease_duration", 3600))

        if verbose:
            ui.info(f"📍 IP LAN: {lan_ip}")
            try:
                ext_ip = client.get_external_ip()
                ui.info(f"🌐 IP WAN: {ext_ip}")
            except Exception:
                pass
            ui.info("")

        if dry_run:
            ui.info("🔥 DRY-RUN mode: no changes will be applied")
            ui.info("")

        processed, failed = reconcile_port_forwards(
            desired, client, lan_ip, lease, dry_run=dry_run, prune=prune, out=ui.info
        )

        ui.info("")
        if failed == 0:
            status = "dry-run" if dry_run else "OK"
            ui.ok(f"{processed}/{len(desired)} port-forwards procesados [{status}]")
        else:
            ui.warn(f"{processed}/{len(desired)} procesados, {failed} fallaron")
            logger.warning("reconcile: %d/%d failed", failed, len(desired))

        return 0 if failed == 0 else 1
