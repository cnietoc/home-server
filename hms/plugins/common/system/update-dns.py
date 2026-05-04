"""
Plugin: system update-dns
Actualiza registros DNS de Cloudflare para el dominio base.
"""

import logging
from typing import List, Optional

from hms.core.plugin import GlobalPlugin
from hms.lib import ui
from hms.lib.cloudflare import CloudflareClient, CloudflareError, get_cloudflare_client

logger = logging.getLogger(__name__)


class UpdateDNSPlugin(GlobalPlugin):
    """Actualizar registros DNS en Cloudflare."""

    def get_name(self) -> str:
        return "update-dns"

    def get_description(self) -> str:
        return "Actualizar registros DNS en Cloudflare"

    def get_help(self) -> str:
        return """
Update DNS - Actualizar registros DNS en Cloudflare

USAGE:
  hms system update-dns [OPTIONS]

DESCRIPTION:
  Actualiza registros DNS A (raíz y wildcard) en Cloudflare para apuntar a la IP
  pública actual del servidor. Detecta automáticamente la IP si no se especifica.

OPTIONS:
  --ip IP              Usar IP específica (por defecto: detectar automáticamente)
  --domain DOMAIN      Dominio específico (por defecto: usar BASE_DOMAIN)
  --dry-run           Solo mostrar qué cambios se harían, sin aplicarlos
  --force             Forzar actualización aunque la IP no haya cambiado
  --list              Listar registros DNS actuales
  -v, --verbose       Mostrar información detallada
  -h, --help          Mostrar esta ayuda

EXAMPLES:
  hms system update-dns                    # Detectar IP y actualizar DNS
  hms system update-dns --ip 192.168.1.100 # Usar IP específica
  hms system update-dns --dry-run          # Ver qué cambios se harían
  hms system update-dns --list             # Ver registros DNS actuales
  hms system update-dns --force            # Forzar actualización

CONFIGURATION:
  Requiere estar configurados:
  - CLOUDFLARE_DNS_API_TOKEN en config/private/cloudflare.env
  - BASE_DOMAIN en config/private/common.env

REGISTROS QUE SE CREAN/ACTUALIZAN:
  - @ (dominio raíz)         → IP del servidor
  - * (wildcard)             → IP del servidor
"""

    def run(self, args: List[str]) -> int:
        """Execute plugin."""
        target_ip: Optional[str] = None
        target_domain: Optional[str] = None
        dry_run = False
        force = False
        list_only = False
        verbose = False

        i = 0
        while i < len(args):
            arg = args[i]

            if arg == "--help" or arg == "-h":
                print(self.get_help())
                return 0
            elif arg == "--ip":
                if i + 1 >= len(args):
                    ui.err("--ip requiere un valor")
                    return 1
                target_ip = args[i + 1]
                i += 2
            elif arg == "--domain":
                if i + 1 >= len(args):
                    ui.err("--domain requiere un valor")
                    return 1
                target_domain = args[i + 1]
                i += 2
            elif arg == "--dry-run":
                dry_run = True
                i += 1
            elif arg == "--force":
                force = True
                i += 1
            elif arg == "--list":
                list_only = True
                i += 1
            elif arg == "-v" or arg == "--verbose":
                verbose = True
                i += 1
            else:
                ui.err(f"Argumento desconocido: {arg}")
                return 1

        try:
            client = get_cloudflare_client()

            if list_only:
                return self._list_records(client)

            return self._update_dns(
                client,
                target_ip=target_ip,
                target_domain=target_domain,
                dry_run=dry_run,
                force=force,
                verbose=verbose,
            )

        except CloudflareError as e:
            ui.err(f"Error: {e}")
            logger.error("update-dns CloudflareError: %s", e)
            return 1
        except Exception:
            ui.err("Error inesperado en update-dns")
            logger.exception("update-dns unexpected error")
            return 1

    def _list_records(self, client: CloudflareClient) -> int:
        """Listar registros DNS actuales."""
        try:
            ui.info(f"📋 Registros DNS para {client.base_domain}:")
            ui.info("")

            records = client.list_records("A")
            if not records:
                ui.info("  (sin registros A)")
            else:
                for record in records:
                    name = record.get("name", "?")
                    content = record.get("content", "?")
                    ttl = record.get("ttl", "?")
                    proxied = "✅ Proxied" if record.get("proxied") else "❌ DNS Only"
                    ui.info(f"  {name:<30} {content:<15} (TTL: {ttl}, {proxied})")

            ui.info("")
            return 0

        except CloudflareError as e:
            ui.err(f"Error listando registros: {e}")
            logger.error("list_records CloudflareError: %s", e)
            return 1

    def _update_dns(
        self,
        client: CloudflareClient,
        target_ip: Optional[str] = None,
        target_domain: Optional[str] = None,
        dry_run: bool = False,
        force: bool = False,
        verbose: bool = False,
    ) -> int:
        """Actualizar registros DNS."""
        try:
            if not target_ip:
                target_ip = client.get_public_ip()
            else:
                ui.info(f"🎯 Usando IP especificada: {target_ip}")

            if target_domain:
                ui.info(f"🎯 Usando dominio especificado: {target_domain}")
                if target_domain != client.base_domain:
                    client = CloudflareClient(client.api_token, target_domain)
            else:
                target_domain = client.base_domain

            ui.info(f"🌐 Dominio objetivo: {target_domain}")
            ui.info(f"📍 IP objetivo: {target_ip}")

            if dry_run:
                ui.info("🔥 Modo DRY-RUN: No se aplicarán cambios reales")

            records_to_update = ["@", "*"]
            results = []
            success_count = 0

            ui.info("")
            ui.info("🚀 Actualizando registros DNS...")
            ui.info("")

            for record_name in records_to_update:
                try:
                    result = client.update_record(
                        record_name,
                        target_ip,
                        ttl=300,
                        proxied=False,
                        dry_run=dry_run,
                        force=force,
                    )
                    results.append(result)

                    if result["status"] in ["updated", "created", "unchanged"]:
                        success_count += 1

                except CloudflareError as e:
                    ui.err(f"Error actualizando {record_name}: {e}")
                    logger.error("update_record '%s' failed: %s", record_name, e)
                    results.append({
                        "status": "error",
                        "name": record_name,
                        "message": str(e),
                    })

            ui.info("")
            ui.info(f"📊 Resultado: {success_count}/{len(records_to_update)} registros procesados")

            if success_count == len(records_to_update):
                message = "DNS actualizado correctamente" if not dry_run else "Cambios listos para aplicar"
                ui.ok(message)
                ui.info("")
                ui.info(f"🌐 Servicios accesibles en:")
                ui.info(f"   https://{target_domain}")
                ui.info(f"   https://*.{target_domain}")
            else:
                ui.warn("Algunos registros tuvieron problemas")

            return 0 if success_count == len(records_to_update) else 1

        except CloudflareError as e:
            ui.err(f"Error: {e}")
            logger.error("_update_dns CloudflareError: %s", e)
            return 1
        except Exception:
            ui.err("Error inesperado en _update_dns")
            logger.exception("_update_dns unexpected error")
            return 1
