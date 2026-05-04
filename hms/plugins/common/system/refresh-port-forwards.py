"""
Plugin: system refresh-port-forwards
Refresca mapeos de puertos en el router via UPnP IGD o NAT-PMP.
"""

import logging
from typing import List

from hms.core.plugin import GlobalPlugin

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
        dry_run = False
        list_only = False
        prune = False
        verbose = False

        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("--help", "-h"):
                logger.info(self.get_help())
                return 0
            elif arg == "--dry-run":
                dry_run = True
            elif arg == "--list":
                list_only = True
            elif arg == "--prune":
                prune = True
            elif arg in ("-v", "--verbose"):
                verbose = True
            else:
                logger.error(f"❌ Argumento desconocido: {arg}")
                return 1
            i += 1

        from hms.lib.config import config_manager
        from hms.lib.router import (
            RouterError,
            get_router_client,
        )

        cfg = config_manager.get_router_config()
        if not cfg.get("enabled", True):
            logger.info("ℹ️  Port-forwarding desactivado (router.enabled = false)")
            return 0

        try:
            client = get_router_client()
        except RouterError as e:
            logger.error(f"❌ Router: {e}")
            return 1
        except Exception as e:
            logger.error(f"❌ Error inesperado al conectar con el router: {e}")
            return 1

        if list_only:
            return self._list_mappings(client, cfg)

        return self._reconcile(client, cfg, dry_run=dry_run, prune=prune, verbose=verbose)

    def _list_mappings(self, client, cfg: dict) -> int:
        try:
            mappings = client.list_mappings()
        except Exception as e:
            logger.error(f"❌ No se pudieron listar mapeos: {e}")
            return 1

        if not mappings:
            logger.info("ℹ️  No hay mapeos activos (o el backend no soporta enumeración)")
            return 0

        try:
            ext_ip = client.get_external_ip()
            logger.info(f"🌐 IP pública: {ext_ip}")
        except Exception:
            pass

        logger.info(f"📋 Mapeos activos en el router ({len(mappings)}):")
        logger.info("")
        for m in mappings:
            port = m.get("ext_port", "?")
            proto = m.get("protocol", "?")
            dest = f"{m.get('int_client', '?')}:{m.get('int_port', '?')}"
            desc = m.get("description", "")
            lease = m.get("lease_time", 0)
            lease_str = f"lease: {lease}s" if lease else "lease: permanente"
            logger.info(f"  {port:<6}/{proto:<4} → {dest:<22} {desc!r:<35} ({lease_str})")

        logger.info("")
        return 0

    def _reconcile(self, client, cfg: dict, dry_run: bool, prune: bool, verbose: bool) -> int:
        from hms.lib.config import config_manager
        from hms.lib.router import RouterError, RouterConflictError, get_desired_mappings

        exclude = cfg.get("exclude_stacks", [])
        desired = get_desired_mappings(exclude_stacks=exclude)

        if not desired:
            logger.info("ℹ️  Ningún stack tiene public_ports declarados")
            return 0

        lan_ip = config_manager.get_global_config().get("host_ip", "")
        if not lan_ip:
            logger.error("❌ global.host_ip no configurado. Ejecuta `hms install` o añádelo a config.toml.")
            return 1
        lease = int(cfg.get("lease_duration", 3600))

        if verbose:
            logger.info(f"📍 IP LAN: {lan_ip}")
            try:
                ext_ip = client.get_external_ip()
                logger.info(f"🌐 IP WAN: {ext_ip}")
            except Exception:
                pass
            logger.info("")

        if dry_run:
            logger.info("🔥 Modo DRY-RUN: no se aplicarán cambios")
            logger.info("")

        # Obtener mapeos actuales (para --prune y para log)
        try:
            current = client.list_mappings()
        except Exception:
            current = []

        current_keys = {
            (m["ext_port"], m["protocol"].lower())
            for m in current
        }

        desired_keys = {(pm.port, pm.protocol) for pm in desired}

        added = 0
        failed = 0

        logger.info(f"🔄 Reconciliando {len(desired)} port-forward(s)...")
        logger.info("")

        for pm in desired:
            exists = (pm.port, pm.protocol) in current_keys
            action = "🔄 refresh" if exists else "➕ añadir"
            logger.info(f"  {action}  {pm.port}/{pm.protocol}  →  {lan_ip}  [{pm.stack}]")

            if not dry_run:
                try:
                    client.add_mapping(pm, lan_ip, lease)
                    added += 1
                except RouterConflictError as e:
                    logger.info(f"    ℹ️  {e}")
                    added += 1
                except Exception as e:
                    logger.warning(f"    ⚠️  {pm.port}/{pm.protocol}: {e}")
                    failed += 1
            else:
                added += 1

        if prune:
            stale_keys = current_keys - desired_keys
            if stale_keys:
                logger.info("")
                logger.info(f"🧹 Eliminando {len(stale_keys)} mapeo(s) obsoleto(s)...")
                for port, proto in stale_keys:
                    logger.info(f"  🗑️  {port}/{proto}")
                    if not dry_run:
                        try:
                            client.delete_mapping(port, proto)
                        except RouterError as e:
                            logger.warning(f"    ⚠️  {e}")

        logger.info("")
        if failed == 0:
            status = "dry-run" if dry_run else "OK"
            logger.info(f"✅ {added}/{len(desired)} port-forwards procesados [{status}]")
        else:
            logger.warning(f"⚠️  {added}/{len(desired)} procesados, {failed} fallaron")

        return 0 if failed == 0 else 1
