"""
Plugin: system refresh-port-forwards
Refresca mapeos de puertos en el router via UPnP IGD o NAT-PMP.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin
from hms.lib import ui

logger = logging.getLogger(__name__)


class RefreshPortForwardsPlugin(GlobalPlugin):
    """Refrescar port-forwards UPnP/NAT-PMP en el router."""

    def get_name(self) -> str:
        return "refresh-port-forwards"

    def get_description(self) -> str:
        return "Refrescar port-forwards UPnP/NAT-PMP en el router"

    def get_help(self) -> str:
        return """
refresh-port-forwards - Refrescar port-forwards en el router

USAGE:
  hms system refresh-port-forwards [OPTIONS]

DESCRIPTION:
  Reconcilia los mapeos de puertos del router con los declarados en
  x-hms.public_ports de cada stack habilitado. Añade los que faltan y
  refresca los existentes para renovar el lease UPnP.

  Este comando se ejecuta automáticamente al arrancar HMS y cada 30 min.

OPTIONS:
  --dry-run     Solo mostrar qué cambios se harían, sin aplicarlos
  --list        Listar mapeos activos en el router
  --prune       Eliminar del router mapeos que ya no estén declarados
  -v, --verbose Mostrar información detallada
  -h, --help    Mostrar esta ayuda

CONFIGURACIÓN:
  [global]
  host_ip = "192.168.X.X"   # IP del host (requerido; se autoconfigura en `hms install`)

  [router]
  enabled        = true
  backend        = "upnp"   # "upnp" | "natpmp" | "none"
  gateway_ip     = ""       # IP del router (vacío = autodetección)
  lease_duration = "3600"   # segundos

EJEMPLOS:
  hms system refresh-port-forwards              # Reconciliar
  hms system refresh-port-forwards --list       # Ver estado del router
  hms system refresh-port-forwards --dry-run    # Ver qué cambiaría
  hms system refresh-port-forwards --prune      # Limpiar mapeos obsoletos
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
                    ui.err("--stack requiere un argumento")
                    return 1
                stack_name = args[i]
            elif arg == "--remove":
                remove = True
            else:
                ui.err(f"Argumento desconocido: {arg}")
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
            ui.info("ℹ️  Port-forwarding desactivado (router.enabled = false)")
            return 0

        try:
            client = get_router_client()
        except RouterError as e:
            ui.err(f"Router: {e}")
            logger.error("Router connect failed: %s", e)
            return 1
        except Exception:
            ui.err("Error inesperado al conectar con el router")
            logger.exception("Router connect failed")
            return 1

        if list_only:
            return self._list_mappings(client, cfg)

        return self._reconcile(client, cfg, dry_run=dry_run, prune=prune, verbose=verbose)

    def _list_mappings(self, client, cfg: dict) -> int:
        try:
            mappings = client.list_mappings()
        except Exception:
            ui.err("No se pudieron listar los mapeos del router")
            logger.exception("list_mappings failed")
            return 1

        if not mappings:
            ui.info("ℹ️  No hay mapeos activos (o el backend no soporta enumeración)")
            return 0

        try:
            ext_ip = client.get_external_ip()
            ui.info(f"🌐 IP pública: {ext_ip}")
        except Exception:
            pass

        ui.info(f"📋 Mapeos activos en el router ({len(mappings)}):")
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
            ui.info("ℹ️  Ningún stack tiene public_ports declarados")
            return 0

        lan_ip = config_manager.get_global_config().get("host_ip", "")
        if not lan_ip:
            ui.err("global.host_ip no configurado. Ejecuta `hms install` o añádelo a config.toml.")
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
            ui.info("🔥 Modo DRY-RUN: no se aplicarán cambios")
            ui.info("")

        processed, failed = reconcile_port_forwards(
            desired, client, lan_ip, lease, dry_run=dry_run, prune=prune
        )

        ui.info("")
        if failed == 0:
            status = "dry-run" if dry_run else "OK"
            ui.ok(f"{processed}/{len(desired)} port-forwards procesados [{status}]")
        else:
            ui.warn(f"{processed}/{len(desired)} procesados, {failed} fallaron")
            logger.warning("reconcile: %d/%d failed", failed, len(desired))

        return 0 if failed == 0 else 1
