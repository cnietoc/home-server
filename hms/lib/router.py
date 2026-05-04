"""
Gestión de port-forwarding automático en el router (UPnP IGD / NAT-PMP).

Expone:
  - PortMapping           — descripción de un mapeo deseado
  - RouterClient          — Protocol común a todos los backends
  - UpnpClient            — Backend UPnP IGD (miniupnpc)
  - NatpmpClient          — Backend NAT-PMP / PCP (libnatpmp, lazy-import)
  - NoopClient            — Backend "none", no-op
  - get_router_client()   — Factory que lee [router] de config
  - detect_lan_ip()       — Detecta IP LAN del host
  - apply_port_forwards_for_stack()  — Aplica forwards para un stack
  - remove_port_forwards_for_stack() — Elimina forwards de un stack
"""

import logging
import socket
from typing import NamedTuple, Literal, Protocol, runtime_checkable

logger = logging.getLogger(__name__)


class RouterError(Exception):
    pass


class RouterConflictError(RouterError):
    """Puerto ya mapeado por una regla estática o cliente externo."""
    pass


class PortMapping(NamedTuple):
    stack: str
    port: int
    protocol: Literal["tcp", "udp"]
    description: str


@runtime_checkable
class RouterClient(Protocol):
    def list_mappings(self) -> list[dict]:
        """Devuelve mapeos activos del router (formato libre, para mostrar al usuario)."""
        ...

    def add_mapping(self, m: PortMapping, lan_ip: str, lease: int) -> None:
        """Añade o refresca un mapeo. Idempotente si ya existe."""
        ...

    def delete_mapping(self, port: int, protocol: str) -> bool:
        """Elimina un mapeo si existe; no-op si no existe. Devuelve True si se eliminó."""
        ...

    def get_external_ip(self) -> str:
        """Devuelve la IP pública WAN del router."""
        ...


# ---------------------------------------------------------------------------
# UPnP backend
# ---------------------------------------------------------------------------

class UpnpClient:
    """Backend UPnP IGD usando miniupnpc."""

    def __init__(self, config: dict):
        self._lease = int(config.get("lease_duration", 3600))
        self._gateway_ip = config.get("gateway_ip", "")
        self._upnp = None  # lazy

    def _get_upnp(self):
        if self._upnp is not None:
            return self._upnp
        try:
            import miniupnpc
        except ImportError:
            raise RouterError(
                "miniupnpc no está instalado. Ejecuta: uv pip install miniupnpc"
            )
        u = miniupnpc.UPnP()
        u.discoverdelay = 500
        ndevices = u.discover()
        if ndevices == 0:
            raise RouterError(
                "No se encontró ningún dispositivo UPnP IGD en la red. "
                "Comprueba que UPnP esté habilitado en el router y que HMS tenga "
                "acceso a la red local (usa network_mode: host si corre en Docker)."
            )
        u.selectigd()
        self._upnp = u
        return u

    def get_external_ip(self) -> str:
        return self._get_upnp().externalipaddress()

    def list_mappings(self) -> list[dict]:
        u = self._get_upnp()
        results = []
        idx = 0
        while True:
            entry = u.getgenericportmapping(idx)
            if entry is None:
                break
            ext_port, proto, (int_client, int_port), desc, enabled, remote_host, lease_time = entry
            results.append({
                "ext_port": ext_port,
                "protocol": proto,
                "int_client": int_client,
                "int_port": int_port,
                "description": desc,
                "enabled": enabled,
                "lease_time": lease_time,
            })
            idx += 1
        return results

    def add_mapping(self, m: PortMapping, lan_ip: str, lease: int) -> None:
        proto = m.protocol.upper()
        desc = f"hms:{m.stack}:{m.description}" if m.description else f"hms:{m.stack}"
        try:
            u = self._get_upnp()
            result = u.addportmapping(m.port, proto, lan_ip, m.port, desc, "", lease)
            if result is False:
                raise RouterError(f"addportmapping devolvió False para {m.port}/{proto}")
        except RouterError:
            raise
        except Exception as e:
            if str(e) == "ConflictInMappingEntry":
                # Port already forwarded by a static/external rule — not an error
                raise RouterConflictError(f"{m.port}/{proto} ya mapeado por regla externa") from e
            raise RouterError(f"No se pudo añadir mapeo {m.port}/{proto}: {e}") from e


    def delete_mapping(self, port: int, protocol: str) -> bool:
        proto = protocol.upper()
        try:
            u = self._get_upnp()
            existing = u.getspecificportmapping(port, proto)
            if existing is None:
                return False
            u.deleteportmapping(port, proto)
            return True
        except RouterError:
            raise
        except Exception as e:
            raise RouterError(f"No se pudo eliminar mapeo {port}/{proto}: {e}") from e


# ---------------------------------------------------------------------------
# NAT-PMP backend
# ---------------------------------------------------------------------------

class NatpmpClient:
    """Backend NAT-PMP usando libnatpmp (lazy-import). Funciona sin SSDP multicast."""

    def __init__(self, config: dict):
        self._lease = int(config.get("lease_duration", 3600))
        self._gateway_ip = config.get("gateway_ip", "")

    def _detect_gateway(self) -> str:
        if self._gateway_ip:
            return self._gateway_ip
        # Detectar gateway por defecto
        gw = _detect_default_gateway()
        if not gw:
            raise RouterError(
                "No se pudo detectar el gateway. Configura router.gateway_ip en config.toml."
            )
        return gw

    def get_external_ip(self) -> str:
        try:
            import natpmp
        except ImportError:
            raise RouterError("libnatpmp no está instalado. Ejecuta: uv pip install libnatpmp")
        gw = self._detect_gateway()
        resp = natpmp.get_public_address(gateway=gw)
        return resp.public_address

    def list_mappings(self) -> list[dict]:
        # NAT-PMP no soporta enumerar mapeos activos
        return []

    def add_mapping(self, m: PortMapping, lan_ip: str, lease: int) -> None:
        try:
            import natpmp
        except ImportError:
            raise RouterError("libnatpmp no está instalado. Ejecuta: uv pip install libnatpmp")
        gw = self._detect_gateway()
        proto = natpmp.NATPMP_PROTOCOL_TCP if m.protocol == "tcp" else natpmp.NATPMP_PROTOCOL_UDP
        natpmp.map_port(proto, m.port, m.port, lease, gateway=gw)


    def delete_mapping(self, port: int, protocol: str) -> bool:
        try:
            import natpmp
        except ImportError:
            raise RouterError("libnatpmp no está instalado. Ejecuta: uv pip install libnatpmp")
        gw = self._detect_gateway()
        proto = natpmp.NATPMP_PROTOCOL_TCP if protocol == "tcp" else natpmp.NATPMP_PROTOCOL_UDP
        # Lease de 0 elimina el mapeo en NAT-PMP; no hay forma de saber si existía
        natpmp.map_port(proto, port, 0, 0, gateway=gw)
        return True


# ---------------------------------------------------------------------------
# No-op backend
# ---------------------------------------------------------------------------

class NoopClient:
    """Backend vacío para router.backend = 'none' o router.enabled = false."""

    def get_external_ip(self) -> str:
        return ""

    def list_mappings(self) -> list[dict]:
        return []


    def add_mapping(self, m: PortMapping, lan_ip: str, lease: int) -> None:
        pass

    def delete_mapping(self, port: int, protocol: str) -> bool:
        return False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _is_docker_ip(ip: str) -> bool:
    """Devuelve True si la IP está en el rango Docker (172.16.0.0/12)."""
    try:
        import ipaddress
        return ipaddress.ip_address(ip) in ipaddress.ip_network("172.16.0.0/12")
    except ValueError:
        return False


def detect_lan_ip(gateway: str = "8.8.8.8") -> str:
    """
    Detecta la IP LAN del host usando el truco UDP estándar.
    Lanza RouterError si detecta una IP de red Docker interna (172.16.0.0/12),
    ya que HMS corre en Docker por defecto y no puede autodetectar la IP del host.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.connect((gateway, 80))
        ip = s.getsockname()[0]

    if _is_docker_ip(ip):
        raise RouterError(
            f"IP autodetectada ({ip}) es una red interna de Docker, no la LAN del host. "
            "Añade la IP real del servidor a config.toml:\n\n"
            "  [router]\n"
            "  lan_ip = \"192.168.X.X\"\n"
        )

    return ip


def _detect_default_gateway() -> str:
    """Intenta detectar la IP del gateway por defecto leyendo /proc/net/route."""
    try:
        with open("/proc/net/route") as f:
            for line in f:
                fields = line.strip().split()
                if fields[1] == "00000000" and fields[3] == "0003":  # default route
                    gw_hex = fields[2]
                    # Formato little-endian hex
                    gw_bytes = bytes.fromhex(gw_hex)
                    return socket.inet_ntoa(gw_bytes[::-1])
    except Exception:
        pass
    # Fallback: buscar en la tabla de rutas con socket
    try:
        import subprocess
        result = subprocess.run(
            ["ip", "route", "show", "default"],
            capture_output=True, text=True, timeout=3
        )
        for line in result.stdout.splitlines():
            parts = line.split()
            if "via" in parts:
                return parts[parts.index("via") + 1]
    except Exception:
        pass
    return ""


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

def get_router_client() -> RouterClient:
    """Crea el cliente de router según [router] de config.toml."""
    from hms.lib.config import config_manager

    cfg = config_manager.get_router_config()
    if not cfg.get("enabled", True):
        return NoopClient()

    backend = cfg.get("backend", "upnp")
    if backend == "upnp":
        return UpnpClient(cfg)
    elif backend == "natpmp":
        return NatpmpClient(cfg)
    elif backend == "none":
        return NoopClient()
    else:
        logger.warning(f"Backend de router desconocido: '{backend}', usando no-op")
        return NoopClient()


# ---------------------------------------------------------------------------
# High-level helpers
# ---------------------------------------------------------------------------

def _log_current_mappings(current_list: list[dict], out=None) -> None:
    def _out(msg):
        if out is not None:
            logger.info(msg)
        (out or logger.info)(msg)
    if current_list:
        _out(f"📋 Mapeos activos en el router ({len(current_list)}):")
        for m in current_list:
            port = m.get("ext_port", "?")
            proto = m.get("protocol", "?").lower()
            dest = f"{m.get('int_client', '?')}:{m.get('int_port', '?')}"
            desc = m.get("description", "")
            lease_time = m.get("lease_time", 0)
            lease_str = f"{lease_time}s" if lease_time else "permanente"
            _out(f"    {port}/{proto} → {dest}  {desc!r}  lease:{lease_str}")
    else:
        _out("📋 Sin mapeos activos en el router")


def reconcile_port_forwards(
    desired: list[PortMapping],
    client: RouterClient,
    lan_ip: str,
    lease: int,
    dry_run: bool = False,
    prune: bool = False,
    out=None,
) -> tuple[int, int]:
    """
    Reconcilia los port-forwards deseados contra el estado actual del router.
    Loguea los mapeos existentes, aplica los cambios y opcionalmente poda los obsoletos.
    Devuelve (procesados, fallidos).
    """
    def _out(msg):
        if out is not None:
            logger.info(msg)
        (out or logger.info)(msg)

    try:
        current_list = client.list_mappings()
    except Exception:
        current_list = []

    _log_current_mappings(current_list, out=_out)
    _out("")

    current_keys = {(m["ext_port"], m["protocol"].lower()) for m in current_list}
    desired_keys = {(pm.port, pm.protocol) for pm in desired}

    processed = 0
    failed = 0

    _out(f"🔄 Reconciliando {len(desired)} port-forward(s)...")
    _out("")

    for pm in desired:
        exists = (pm.port, pm.protocol) in current_keys
        action = "🔄 refresh" if exists else "➕ añadir"
        _out(f"  {action}  {pm.port}/{pm.protocol}  →  {lan_ip}  [{pm.stack}]")
        if not dry_run:
            try:
                client.add_mapping(pm, lan_ip, lease)
                processed += 1
            except RouterConflictError as e:
                _out(f"    ℹ️  {e}")
                processed += 1
            except Exception as e:
                logger.warning("port-forward %s/%s failed: %s", pm.port, pm.protocol, e)
                _out(f"    ⚠️  {pm.port}/{pm.protocol}: {e}")
                failed += 1
        else:
            processed += 1

    if prune:
        stale_keys = current_keys - desired_keys
        if stale_keys:
            _out("")
            _out(f"🧹 Eliminando {len(stale_keys)} mapeo(s) obsoleto(s)...")
            for port, proto in stale_keys:
                _out(f"  🗑️  {port}/{proto}")
                if not dry_run:
                    try:
                        client.delete_mapping(port, proto)
                    except RouterError as e:
                        logger.warning("delete_mapping %s/%s failed: %s", port, proto, e)
                        _out(f"    ⚠️  {e}")

    return processed, failed


def apply_port_forwards_for_stack(stack_name: str) -> None:
    """Aplica port-forwards del router para un stack. Lanza efímero con host networking."""
    from hms.lib.config import config_manager
    from hms.lib.stacks import stack_metadata
    from hms.lib.host_runner import run_hms_in_host_network, HostRunnerError

    cfg = config_manager.get_router_config()
    if not cfg.get("enabled", True):
        return
    if stack_name in cfg.get("exclude_stacks", []):
        logger.debug(f"Stack '{stack_name}' en exclude_stacks, omitiendo port-forwards")
        return
    if not stack_metadata.get_public_ports(stack_name):
        return

    try:
        run_hms_in_host_network(["system", "refresh-port-forwards", "--stack", stack_name])
    except HostRunnerError as e:
        logger.warning(f"⚠️  Router: {e}")


def remove_port_forwards_for_stack(stack_name: str) -> None:
    """Elimina port-forwards del router para un stack. Lanza efímero con host networking."""
    from hms.lib.config import config_manager
    from hms.lib.stacks import stack_metadata
    from hms.lib.host_runner import run_hms_in_host_network, HostRunnerError

    cfg = config_manager.get_router_config()
    if not cfg.get("enabled", True):
        return
    if stack_name in cfg.get("exclude_stacks", []):
        return
    if not stack_metadata.get_public_ports(stack_name):
        return

    try:
        run_hms_in_host_network(["system", "refresh-port-forwards", "--stack", stack_name, "--remove"])
    except HostRunnerError as e:
        logger.warning(f"⚠️  Router: {e}")


def _apply_ports_for_stack(stack_name: str) -> None:
    """Aplica port-forwards in-process. Solo llamar con host networking activo."""
    from hms.lib.config import config_manager
    from hms.lib.stacks import stack_metadata

    cfg = config_manager.get_router_config()
    if not cfg.get("enabled", True):
        return
    if stack_name in cfg.get("exclude_stacks", []):
        logger.debug(f"Stack '{stack_name}' en exclude_stacks, omitiendo port-forwards")
        return

    ports = stack_metadata.get_public_ports(stack_name)
    if not ports:
        return

    lan_ip = config_manager.get_global_config().get("host_ip", "")
    if not lan_ip:
        logger.warning("⚠️  Router: global.host_ip no configurado. Ejecuta `hms install` o añádelo a config.toml.")
        return
    lease = int(cfg.get("lease_duration", 3600))

    try:
        client = get_router_client()
    except RouterError as e:
        logger.warning(f"⚠️  Router: {e}")
        return

    reconcile_port_forwards(ports, client, lan_ip, lease)


def _remove_ports_for_stack(stack_name: str) -> None:
    """Elimina port-forwards in-process. Solo llamar con host networking activo."""
    from hms.lib.config import config_manager
    from hms.lib.stacks import stack_metadata

    cfg = config_manager.get_router_config()
    if not cfg.get("enabled", True):
        return
    if stack_name in cfg.get("exclude_stacks", []):
        return

    ports = stack_metadata.get_public_ports(stack_name)
    if not ports:
        return

    try:
        client = get_router_client()
    except RouterError as e:
        logger.warning(f"⚠️  Router: {e}")
        return

    for pm in ports:
        try:
            if client.delete_mapping(pm.port, pm.protocol):
                logger.info(f"🔌 Router: eliminado {pm.port}/{pm.protocol} [{pm.stack}]")
        except RouterError as e:
            logger.warning(f"⚠️  Router: no se pudo eliminar {pm.port}/{pm.protocol}: {e}")


def get_desired_mappings(exclude_stacks: list[str] | None = None) -> list[PortMapping]:
    """Devuelve todos los PortMapping deseados para los stacks habilitados."""
    from hms.lib.config import config_manager
    from hms.lib.stacks import stack_metadata

    exclude = exclude_stacks or []
    desired = []
    for stack_name in stack_metadata.list_stacks():
        if stack_name in exclude:
            continue
        if not config_manager.is_stack_enabled(stack_name):
            continue
        desired.extend(stack_metadata.get_public_ports(stack_name))
    return desired
