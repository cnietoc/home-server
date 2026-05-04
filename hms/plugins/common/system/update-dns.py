"""
Plugin: system update-dns
Updates Cloudflare DNS records for the base domain.
"""

import logging
from typing import List, Optional

from hms.core.plugin import GlobalPlugin
from hms.lib import ui
from hms.lib.cloudflare import CloudflareClient, CloudflareError, get_cloudflare_client

logger = logging.getLogger(__name__)


class UpdateDNSPlugin(GlobalPlugin):
    """Update DNS records in Cloudflare."""

    def get_name(self) -> str:
        return "update-dns"

    def get_description(self) -> str:
        return "Update DNS records in Cloudflare"

    def get_help(self) -> str:
        return """
Update DNS - Update DNS records in Cloudflare

USAGE:
  hms system update-dns [OPTIONS]

DESCRIPTION:
  Updates DNS A records (root and wildcard) in Cloudflare to point to the
  server's current public IP. Auto-detects the IP if not specified.

OPTIONS:
  --ip IP              Use a specific IP (default: auto-detect)
  --domain DOMAIN      Specific domain (default: use BASE_DOMAIN)
  --dry-run           Only show what changes would be made, without applying them
  --force             Force update even if the IP has not changed
  --list              List current DNS records
  -v, --verbose       Show detailed information
  -h, --help          Show this help

EXAMPLES:
  hms system update-dns                    # Auto-detect IP and update DNS
  hms system update-dns --ip 192.168.1.100 # Use a specific IP
  hms system update-dns --dry-run          # Preview what changes would be made
  hms system update-dns --list             # View current DNS records
  hms system update-dns --force            # Force update

CONFIGURATION:
  Required:
  - CLOUDFLARE_DNS_API_TOKEN in config/private/cloudflare.env
  - BASE_DOMAIN in config/private/common.env

RECORDS CREATED/UPDATED:
  - @ (root domain)    → server IP
  - * (wildcard)       → server IP
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
                    ui.err("--ip requires a value")
                    return 1
                target_ip = args[i + 1]
                i += 2
            elif arg == "--domain":
                if i + 1 >= len(args):
                    ui.err("--domain requires a value")
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
                ui.err(f"Unknown argument: {arg}")
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
            ui.err("Unexpected error in update-dns")
            logger.exception("update-dns unexpected error")
            return 1

    def _list_records(self, client: CloudflareClient) -> int:
        """List current DNS records."""
        try:
            ui.info(f"📋 DNS records for {client.base_domain}:")
            ui.info("")

            records = client.list_records("A")
            if not records:
                ui.info("  (no A records)")
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
            ui.err(f"Error listing records: {e}")
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
        """Update DNS records."""
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

            ui.info(f"🌐 Target domain: {target_domain}")
            ui.info(f"📍 Target IP: {target_ip}")

            if dry_run:
                ui.info("🔥 DRY-RUN mode: no real changes will be applied")

            records_to_update = ["@", "*"]
            results = []
            success_count = 0

            ui.info("")
            ui.info("🚀 Updating DNS records...")
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
                    ui.err(f"Error updating {record_name}: {e}")
                    logger.error("update_record '%s' failed: %s", record_name, e)
                    results.append({
                        "status": "error",
                        "name": record_name,
                        "message": str(e),
                    })

            ui.info("")
            ui.info(f"📊 Result: {success_count}/{len(records_to_update)} records processed")

            if success_count == len(records_to_update):
                message = "DNS updated successfully" if not dry_run else "Changes ready to apply"
                ui.ok(message)
                ui.info("")
                ui.info(f"🌐 Services accessible at:")
                ui.info(f"   https://{target_domain}")
                ui.info(f"   https://*.{target_domain}")
            else:
                ui.warn("Some records encountered problems")

            return 0 if success_count == len(records_to_update) else 1

        except CloudflareError as e:
            ui.err(f"Error: {e}")
            logger.error("_update_dns CloudflareError: %s", e)
            return 1
        except Exception:
            ui.err("Unexpected error in _update_dns")
            logger.exception("_update_dns unexpected error")
            return 1
