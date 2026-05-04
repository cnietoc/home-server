"""
Módulo para gestionar estado global del servidor.
Incluye persistencia en data/state.yml.
"""

import logging
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

import yaml
from typing_extensions import deprecated

from hms.lib.paths import get_data_root

logger = logging.getLogger(__name__)


class StateManager:
    """Gestor de estado global en state.yml."""

    def __init__(self, state_file: Optional[Path] = None):
        """
        Inicializar gestor de estado.

        Args:
            state_file: Ruta a state.yml (o auto-detectar)
        """
        if state_file is None:
            state_file = get_data_root() / "state.yml"

        self.state_file = state_file
        self._state: Dict[str, Any] = {}
        self._load()

    def _load(self) -> None:
        """Cargar estado desde archivo."""
        if not self.state_file.exists():
            logger.debug(f"📄 Inicializando {self.state_file.name}")
            self._state = {"server": {}, "stacks": {}}
            self._save()
        else:
            try:
                content = self.state_file.read_text()
                self._state = yaml.safe_load(content) or {"server": {}, "stacks": {}}
                logger.debug(f"✅ Estado cargado desde {self.state_file.name}")
            except Exception:
                logger.exception(f"❌ Error cargando {self.state_file.name}")
                self._state = {"server": {}, "stacks": {}}

    def _save(self) -> None:
        """Guardar estado a archivo."""
        try:
            self.state_file.parent.mkdir(parents=True, exist_ok=True)
            content = yaml.dump(
                self._state,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=True,
            )
            self.state_file.write_text(content)
            logger.debug(f"✅ Estado guardado a {self.state_file.name}")
        except Exception:
            logger.exception(f"❌ Error guardando {self.state_file.name}")

    def get(self, key: str, default: Any = None) -> Any:
        """
        Obtener valor del estado.

        Args:
            key: Ruta punteada (ej: 'server.dns.last_update.ip')
            default: Valor por defecto

        Returns:
            Valor o default
        """
        parts = key.split(".")
        value = self._state

        for part in parts:
            if isinstance(value, dict):
                value = value.get(part)
                if value is None:
                    return default
            else:
                return default

        return value if value is not None else default

    def set(self, key: str, value: Any, save: bool = True) -> None:
        """
        Establecer valor en el estado.

        Args:
            key: Ruta punteada (ej: 'server.dns.last_update.ip')
            value: Valor a establecer
            save: Si guardar inmediatamente
        """
        parts = key.split(".")
        current = self._state

        # Navegar/crear estructura
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]

        # Establecer valor
        current[parts[-1]] = value

        if save:
            self._save()

    def update_dns_state(
        self,
        ip: str,
        domain: str,
        records: list,
        status: str = "success",
        message: str = "",
    ) -> None:
        """
        Actualizar estado DNS.

        Args:
            ip: IP pública detectada
            domain: Dominio actualizado
            records: Lista de registros actualizados
            status: Estado ('success', 'error', 'unchanged')
            message: Mensaje descriptivo
        """
        now = datetime.now(timezone.utc).astimezone()
        timestamp = int(time.time())

        if "server" not in self._state:
            self._state["server"] = {}

        self._state["server"]["dns"] = {
            "last_update": {
                "timestamp": timestamp,
                "date": now.isoformat(),
                "ip": ip,
                "domain": domain,
                "status": status,
                "message": message,
            },
            "records": records,
        }

        self._save()
        logger.debug(f"📝 Estado DNS actualizado: {status}")

    def get_dns_state(self) -> Dict[str, Any]:
        """Obtener estado DNS actual."""
        return self.get("server.dns", {})

    def get_last_dns_ip(self) -> Optional[str]:
        """Obtener última IP DNS conocida (para fallback)."""
        return self.get("server.dns.last_update.ip")

    def get_last_dns_update_time(self) -> Optional[int]:
        """Obtener timestamp del último update DNS."""
        return self.get("server.dns.last_update.timestamp")

    def is_job_enabled(self, job_id: str) -> bool:
        """Verificar si un job está habilitado."""
        return self.get(f"daemon.jobs.{job_id}.enabled", True)

    def set_job_enabled(self, job_id: str, enabled: bool) -> None:
        """Activar o desactivar un job."""
        self.set(f"daemon.jobs.{job_id}.enabled", enabled)

    def get_job_config(self, job_id: str) -> Dict[str, Any]:
        """Obtener configuración de un job."""
        return self.get(f"daemon.jobs.{job_id}", {})

    def set_job_config(self, job_id: str, config: Dict[str, Any]) -> None:
        """Establecer configuración de un job."""
        self.set(f"daemon.jobs.{job_id}", config)

    def get_all_jobs_config(self) -> Dict[str, Any]:
        """Obtener configuración de todos los jobs."""
        return self.get("daemon.jobs", {})

    def get_jobs_config(self) -> Dict[str, Any]:
        """Obtener configuración completa de jobs."""
        cfg = self.get("daemon.jobs", {})
        return cfg if isinstance(cfg, dict) else {}

    def update_job(self, job_id: str, config: Dict[str, Any]) -> None:
        """Actualizar/crear configuración de un job y guardar estado."""
        jobs = self.get_jobs_config()
        jobs[job_id] = config
        self.set("daemon.jobs", jobs)

    def reset_jobs_defaults(self) -> None:
        """Restaurar configuración de jobs a los defaults."""
        from hms.lib.jobs_defaults import get_default_jobs

        self.set("daemon.jobs", get_default_jobs())


@deprecated("Ya no vamos a tener estado más")
def get_state_manager() -> StateManager:
    """Factory function para obtener state manager."""
    return StateManager()
