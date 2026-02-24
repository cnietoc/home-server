"""
Módulo cliente para Cloudflare API.
Maneja detección de IP pública, gestión de registros DNS y caché de estado.
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
    """Excepción base para errores de Cloudflare."""
    pass


class CloudflareClient:
    """Cliente para API de Cloudflare."""

    # Servicios para detectar IP pública (en orden de preferencia)
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
        Inicializar cliente de Cloudflare.

        Args:
            api_token: Token de API de Cloudflare
            base_domain: Dominio base (ej: example.com)

        Raises:
            CloudflareError: Si el token o dominio son inválidos
        """
        if not requests:
            raise CloudflareError(
                "requests library no instalado. Ejecuta: pip install requests"
            )

        if not api_token or not isinstance(api_token, str):
            raise CloudflareError("API token inválido")

        if not base_domain or not isinstance(base_domain, str):
            raise CloudflareError("Dominio base inválido")

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
        Detectar IP pública del servidor.

        Intenta múltiples servicios.

        Returns:
            IP pública detectada

        Raises:
            CloudflareError: Si no se puede detectar y no hay fallback
        """
        logger.debug("🔍 Detectando IP pública...")

        for service in self.IP_DETECTION_SERVICES:
            try:
                response = self._session.get(
                    service,
                    timeout=self.HTTP_TIMEOUT,
                )
                response.raise_for_status()
                ip = response.text.strip()

                # Validar formato de IP
                if self._is_valid_ip(ip):
                    logger.debug(f"✅ IP detectada: {ip} (desde {service.split('/')[2]})")
                    return ip
            except Exception as e:
                logger.debug(f"⚠️  Error en {service}: {e}")
                continue

        raise CloudflareError("No se pudo detectar la IP pública")

    def get_zone_id(self) -> str:
        """
        Obtener Zone ID de Cloudflare para el dominio.

        Returns:
            Zone ID

        Raises:
            CloudflareError: Si el dominio no existe en Cloudflare
        """
        if self._zone_id:
            return self._zone_id

        logger.debug(f"🔍 Obteniendo Zone ID para {self.base_domain}...")

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
                error_msg = errors[0].get("message", "Error desconocido") if errors else "Error desconocido"
                raise CloudflareError(f"API error: {error_msg}")

            results = data.get("result", [])
            if not results:
                raise CloudflareError(
                    f"Dominio {self.base_domain} no encontrado en Cloudflare"
                )

            self._zone_id = results[0]["id"]
            logger.debug(f"✅ Zone ID obtenido: {self._zone_id}")
            return self._zone_id

        except requests.RequestException as e:
            raise CloudflareError(f"Error conectando con Cloudflare API: {e}")

    def list_records(self, record_type: str = "A") -> List[Dict[str, Any]]:
        """
        Listar registros DNS de un tipo específico.

        Args:
            record_type: Tipo de registro (ej: 'A', 'AAAA', 'CNAME')

        Returns:
            Lista de registros

        Raises:
            CloudflareError: Si hay error en la API
        """
        zone_id = self.get_zone_id()
        logger.debug(f"📋 Obteniendo registros {record_type} para {self.base_domain}...")

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
                error_msg = errors[0].get("message", "Error desconocido") if errors else "Error desconocido"
                raise CloudflareError(f"API error: {error_msg}")

            records = data.get("result", [])
            logger.debug(f"✅ {len(records)} registros obtenidos")
            return records

        except requests.RequestException as e:
            raise CloudflareError(f"Error obteniendo registros: {e}")

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
        Crear o actualizar registro DNS.

        Args:
            record_name: Nombre del registro ('@' para raíz, '*' para wildcard)
            ip: IP a asignar
            ttl: TTL en segundos
            proxied: Si el registro está proxiado por Cloudflare
            dry_run: Si True, no aplica cambios
            force: Si True, actualiza aunque la IP sea la misma

        Returns:
            Información del registro actualizado

        Raises:
            CloudflareError: Si hay error en la API o validación
        """
        if not self._is_valid_ip(ip):
            raise CloudflareError(f"IP inválida: {ip}")

        zone_id = self.get_zone_id()
        full_name = self._get_full_record_name(record_name)

        logger.debug(f"🔍 Verificando registro: {full_name}")

        # Obtener registro existente
        try:
            existing_records = self._session.get(
                f"{self.CLOUDFLARE_API_BASE}/zones/{zone_id}/dns_records",
                params={"type": "A", "name": full_name},
                timeout=self.HTTP_TIMEOUT,
            ).json().get("result", [])

            existing_record = existing_records[0] if existing_records else None
        except Exception as e:
            raise CloudflareError(f"Error obteniendo registro existente: {e}")

        if existing_record:
            current_ip = existing_record.get("content", "")

            # Si la IP es la misma y no es --force, retornar sin cambios
            if current_ip == ip and not force:
                logger.info(f"⏭️  {full_name} ya apunta a {ip} (sin cambios)")
                return {
                    "status": "unchanged",
                    "name": full_name,
                    "ip": ip,
                    "message": f"Ya apunta a {ip}",
                }

            logger.info(f"🔄 Actualizando {full_name}: {current_ip} → {ip}")

            if dry_run:
                logger.info(f"🔥 [DRY-RUN] Se actualizaría: {full_name} → {ip}")
                return {
                    "status": "dry_run",
                    "name": full_name,
                    "ip": ip,
                    "message": f"[DRY-RUN] Se actualizaría a {ip}",
                }

            # Actualizar registro existente
            return self._update_dns_record(
                zone_id,
                existing_record["id"],
                full_name,
                ip,
                ttl,
                proxied,
            )
        else:
            logger.info(f"➕ Creando nuevo registro: {full_name} → {ip}")

            if dry_run:
                logger.info(f"🔥 [DRY-RUN] Se crearía: {full_name} → {ip}")
                return {
                    "status": "dry_run",
                    "name": full_name,
                    "ip": ip,
                    "message": f"[DRY-RUN] Se crearía con IP {ip}",
                }

            # Crear nuevo registro
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
        """Actualizar registro DNS existente."""
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
                error_msg = errors[0].get("message", "Error desconocido") if errors else "Error desconocido"
                raise CloudflareError(f"API error: {error_msg}")

            logger.info(f"✅ Actualizado: {full_name} → {ip}")
            return {
                "status": "updated",
                "name": full_name,
                "ip": ip,
                "message": f"Actualizado a {ip}",
            }

        except requests.RequestException as e:
            raise CloudflareError(f"Error actualizando registro: {e}")

    def _create_dns_record(
            self,
            zone_id: str,
            full_name: str,
            ip: str,
            ttl: int,
            proxied: bool,
    ) -> Dict[str, Any]:
        """Crear nuevo registro DNS."""
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
                error_msg = errors[0].get("message", "Error desconocido") if errors else "Error desconocido"
                raise CloudflareError(f"API error: {error_msg}")

            logger.info(f"✅ Creado: {full_name} → {ip}")
            return {
                "status": "created",
                "name": full_name,
                "ip": ip,
                "message": f"Creado con IP {ip}",
            }

        except requests.RequestException as e:
            raise CloudflareError(f"Error creando registro: {e}")

    def _get_full_record_name(self, record_name: str) -> str:
        """Convertir nombre de registro a nombre completo."""
        if record_name == "@":
            return self.base_domain
        elif record_name == "*":
            return f"*.{self.base_domain}"
        else:
            return record_name

    @staticmethod
    def _is_valid_ip(ip: str) -> bool:
        """Validar formato de IP v4."""
        parts = ip.split(".")
        if len(parts) != 4:
            return False
        try:
            return all(0 <= int(part) <= 255 for part in parts)
        except ValueError:
            return False

    def close(self):
        """Cerrar sesión HTTP."""
        if self._session:
            self._session.close()

    def __del__(self):
        """Limpiar recursos."""
        self.close()


def get_cloudflare_client() -> CloudflareClient:
    """
    Factory function para crear cliente de Cloudflare.

    Returns:
        CloudflareClient configurado

    Raises:
        CloudflareError: Si faltan variables de entorno o configuración
    """
    api_token = config_manager.get_config_value("infra.cloudflare.dns_api_token")
    if not api_token:
        raise CloudflareError(
            "Api Token no configurado en infra.cloudflare.dns_api_token"
        )

    base_domain = config_manager.get_config_value("global.domain")
    if not base_domain:
        raise CloudflareError(
            "Dominio base no configurado en global.domain"
        )

    return CloudflareClient(api_token, base_domain)
