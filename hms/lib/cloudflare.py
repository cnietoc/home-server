"""
Cloudflare API client module.
Handles public IP detection, DNS record management, and state caching.
"""

import logging
from typing import Dict, List, Optional, Any

from hms.lib.config import config_manager

try:
    import requests
except ImportError:
    requests = None

logger = logging.getLogger(__name__)


class CloudflareError(Exception):
    """Base exception for Cloudflare errors."""
    pass


class CloudflareClient:
    """Cloudflare API client."""

    # Services for detecting the public IP (in order of preference)
    IP_DETECTION_SERVICES = [
        "https://api.ipify.org",
        "https://ipinfo.io/ip",
        "https://ifconfig.me",
        "https://api.my-ip.io/ip",
    ]

    CLOUDFLARE_API_BASE = "https://api.cloudflare.com/client/v4"
    HTTP_TIMEOUT = 10

    def __init__(self, api_token: str, base_domain: str):
        """
        Initialise the Cloudflare client.

        Args:
            api_token: Cloudflare API token
            base_domain: Base domain (e.g. example.com)

        Raises:
            CloudflareError: If the token or domain are invalid
        """
        if not requests:
            raise CloudflareError(
                "requests library not installed. Run: pip install requests"
            )

        if not api_token or not isinstance(api_token, str):
            raise CloudflareError("Invalid API token")

        if not base_domain or not isinstance(base_domain, str):
            raise CloudflareError("Invalid base domain")

        self.api_token = api_token
        self.base_domain = base_domain
        self._zone_id: Optional[str] = None
        self._session = requests.Session()
        self._session.headers.update({
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json",
        })

    def get_public_ip(self) -> str:
        """
        Detect the server's public IP.

        Tries multiple services.

        Returns:
            Detected public IP

        Raises:
            CloudflareError: If detection fails and there is no fallback
        """
        logger.debug("🔍 Detecting public IP...")

        for service in self.IP_DETECTION_SERVICES:
            try:
                response = self._session.get(
                    service,
                    timeout=self.HTTP_TIMEOUT,
                )
                response.raise_for_status()
                ip = response.text.strip()

                # Validate IP format
                if self._is_valid_ip(ip):
                    logger.debug(f"✅ IP detected: {ip} (from {service.split('/')[2]})")
                    return ip
            except Exception as e:
                logger.debug(f"⚠️  Error at {service}: {e}")
                continue

        raise CloudflareError("Could not detect the public IP")

    def get_zone_id(self) -> str:
        """
        Get the Cloudflare Zone ID for the domain.

        Returns:
            Zone ID

        Raises:
            CloudflareError: If the domain does not exist in Cloudflare
        """
        if self._zone_id:
            return self._zone_id

        logger.debug(f"🔍 Getting Zone ID for {self.base_domain}...")

        try:
            response = self._session.get(
                f"{self.CLOUDFLARE_API_BASE}/zones",
                params={"name": self.base_domain},
                timeout=self.HTTP_TIMEOUT,
            )
            response.raise_for_status()
            data = response.json()

            if not data.get("success"):
                errors = data.get("errors", [])
                error_msg = errors[0].get("message", "Unknown error") if errors else "Unknown error"
                raise CloudflareError(f"API error: {error_msg}")

            results = data.get("result", [])
            if not results:
                raise CloudflareError(
                    f"Domain {self.base_domain} not found in Cloudflare"
                )

            self._zone_id = results[0]["id"]
            logger.debug(f"✅ Zone ID obtained: {self._zone_id}")
            return self._zone_id

        except requests.RequestException as e:
            raise CloudflareError(f"Error connecting to Cloudflare API: {e}")

    def list_records(self, record_type: str = "A") -> List[Dict[str, Any]]:
        """
        List DNS records of a specific type.

        Args:
            record_type: Record type (e.g. 'A', 'AAAA', 'CNAME')

        Returns:
            List of records

        Raises:
            CloudflareError: If there is an API error
        """
        zone_id = self.get_zone_id()
        logger.debug(f"📋 Getting {record_type} records for {self.base_domain}...")

        try:
            response = self._session.get(
                f"{self.CLOUDFLARE_API_BASE}/zones/{zone_id}/dns_records",
                params={"type": record_type},
                timeout=self.HTTP_TIMEOUT,
            )
            response.raise_for_status()
            data = response.json()

            if not data.get("success"):
                errors = data.get("errors", [])
                error_msg = errors[0].get("message", "Unknown error") if errors else "Unknown error"
                raise CloudflareError(f"API error: {error_msg}")

            records = data.get("result", [])
            logger.debug(f"✅ {len(records)} records obtained")
            return records

        except requests.RequestException as e:
            raise CloudflareError(f"Error retrieving records: {e}")

    def update_record(
            self,
            record_name: str,
            ip: str,
            ttl: int = 300,
            proxied: bool = False,
            dry_run: bool = False,
            force: bool = False,
    ) -> Dict[str, Any]:
        """
        Create or update a DNS record.

        Args:
            record_name: Record name ('@' for root, '*' for wildcard)
            ip: IP address to assign
            ttl: TTL in seconds
            proxied: Whether the record is proxied through Cloudflare
            dry_run: If True, no changes are applied
            force: If True, update even if the IP has not changed

        Returns:
            Information about the updated record

        Raises:
            CloudflareError: If there is an API or validation error
        """
        if not self._is_valid_ip(ip):
            raise CloudflareError(f"Invalid IP: {ip}")

        zone_id = self.get_zone_id()
        full_name = self._get_full_record_name(record_name)

        logger.debug(f"🔍 Checking record: {full_name}")

        # Get existing record
        try:
            existing_records = self._session.get(
                f"{self.CLOUDFLARE_API_BASE}/zones/{zone_id}/dns_records",
                params={"type": "A", "name": full_name},
                timeout=self.HTTP_TIMEOUT,
            ).json().get("result", [])

            existing_record = existing_records[0] if existing_records else None
        except Exception as e:
            raise CloudflareError(f"Error retrieving existing record: {e}")

        if existing_record:
            current_ip = existing_record.get("content", "")

            # If the IP is the same and --force is not set, return without changes
            if current_ip == ip and not force:
                logger.info(f"⏭️  {full_name} already points to {ip} (no changes)")
                return {
                    "status": "unchanged",
                    "name": full_name,
                    "ip": ip,
                    "message": f"Already points to {ip}",
                }

            logger.info(f"🔄 Updating {full_name}: {current_ip} → {ip}")

            if dry_run:
                logger.info(f"🔥 [DRY-RUN] Would update: {full_name} → {ip}")
                return {
                    "status": "dry_run",
                    "name": full_name,
                    "ip": ip,
                    "message": f"[DRY-RUN] Would update to {ip}",
                }

            # Update existing record
            return self._update_dns_record(
                zone_id,
                existing_record["id"],
                full_name,
                ip,
                ttl,
                proxied,
            )
        else:
            logger.info(f"➕ Creating new record: {full_name} → {ip}")

            if dry_run:
                logger.info(f"🔥 [DRY-RUN] Would create: {full_name} → {ip}")
                return {
                    "status": "dry_run",
                    "name": full_name,
                    "ip": ip,
                    "message": f"[DRY-RUN] Would create with IP {ip}",
                }

            # Create new record
            return self._create_dns_record(
                zone_id,
                full_name,
                ip,
                ttl,
                proxied,
            )

    def _update_dns_record(
            self,
            zone_id: str,
            record_id: str,
            full_name: str,
            ip: str,
            ttl: int,
            proxied: bool,
    ) -> Dict[str, Any]:
        """Update an existing DNS record."""
        try:
            response = self._session.put(
                f"{self.CLOUDFLARE_API_BASE}/zones/{zone_id}/dns_records/{record_id}",
                json={
                    "type": "A",
                    "name": full_name,
                    "content": ip,
                    "ttl": ttl,
                    "proxied": proxied,
                },
                timeout=self.HTTP_TIMEOUT,
            )
            response.raise_for_status()
            data = response.json()

            if not data.get("success"):
                errors = data.get("errors", [])
                error_msg = errors[0].get("message", "Unknown error") if errors else "Unknown error"
                raise CloudflareError(f"API error: {error_msg}")

            logger.info(f"✅ Updated: {full_name} → {ip}")
            return {
                "status": "updated",
                "name": full_name,
                "ip": ip,
                "message": f"Updated to {ip}",
            }

        except requests.RequestException as e:
            raise CloudflareError(f"Error updating record: {e}")

    def _create_dns_record(
            self,
            zone_id: str,
            full_name: str,
            ip: str,
            ttl: int,
            proxied: bool,
    ) -> Dict[str, Any]:
        """Create a new DNS record."""
        try:
            response = self._session.post(
                f"{self.CLOUDFLARE_API_BASE}/zones/{zone_id}/dns_records",
                json={
                    "type": "A",
                    "name": full_name,
                    "content": ip,
                    "ttl": ttl,
                    "proxied": proxied,
                },
                timeout=self.HTTP_TIMEOUT,
            )
            response.raise_for_status()
            data = response.json()

            if not data.get("success"):
                errors = data.get("errors", [])
                error_msg = errors[0].get("message", "Unknown error") if errors else "Unknown error"
                raise CloudflareError(f"API error: {error_msg}")

            logger.info(f"✅ Created: {full_name} → {ip}")
            return {
                "status": "created",
                "name": full_name,
                "ip": ip,
                "message": f"Created with IP {ip}",
            }

        except requests.RequestException as e:
            raise CloudflareError(f"Error creating record: {e}")

    def _get_full_record_name(self, record_name: str) -> str:
        """Convert record name to fully qualified name."""
        if record_name == "@":
            return self.base_domain
        elif record_name == "*":
            return f"*.{self.base_domain}"
        else:
            return record_name

    @staticmethod
    def _is_valid_ip(ip: str) -> bool:
        """Validate IPv4 format."""
        parts = ip.split(".")
        if len(parts) != 4:
            return False
        try:
            return all(0 <= int(part) <= 255 for part in parts)
        except ValueError:
            return False

    def close(self):
        """Close the HTTP session."""
        if self._session:
            self._session.close()

    def __del__(self):
        """Clean up resources."""
        self.close()


def get_cloudflare_client() -> CloudflareClient:
    """
    Factory function to create a Cloudflare client.

    Returns:
        Configured CloudflareClient

    Raises:
        CloudflareError: If environment variables or configuration are missing
    """
    api_token = config_manager.get_config_value("infra.cloudflare.dns_api_token")
    if not api_token:
        raise CloudflareError(
            "API token not configured at infra.cloudflare.dns_api_token"
        )

    base_domain = config_manager.get_config_value("global.domain")
    if not base_domain:
        raise CloudflareError(
            "Base domain not configured at global.domain"
        )

    return CloudflareClient(api_token, base_domain)
