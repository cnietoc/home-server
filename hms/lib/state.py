"""
Module for managing global server state.
Persists state to data/state.yml.
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
    """Global state manager backed by state.yml."""

    def __init__(self, state_file: Optional[Path] = None):
        """
        Initialise the state manager.

        Args:
            state_file: Path to state.yml (auto-detected if not provided)
        """
        if state_file is None:
            state_file = get_data_root() / "state.yml"

        self.state_file = state_file
        self._state: Dict[str, Any] = {}
        self._load()

    def _load(self) -> None:
        """Load state from file."""
        if not self.state_file.exists():
            logger.debug(f"📄 Initialising {self.state_file.name}")
            self._state = {"server": {}, "stacks": {}}
            self._save()
        else:
            try:
                content = self.state_file.read_text()
                self._state = yaml.safe_load(content) or {"server": {}, "stacks": {}}
                logger.debug(f"✅ State loaded from {self.state_file.name}")
            except Exception:
                logger.exception(f"❌ Error loading {self.state_file.name}")
                self._state = {"server": {}, "stacks": {}}

    def _save(self) -> None:
        """Save state to file."""
        try:
            self.state_file.parent.mkdir(parents=True, exist_ok=True)
            content = yaml.dump(
                self._state,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=True,
            )
            self.state_file.write_text(content)
            logger.debug(f"✅ State saved to {self.state_file.name}")
        except Exception:
            logger.exception(f"❌ Error saving {self.state_file.name}")

    def get(self, key: str, default: Any = None) -> Any:
        """
        Get a value from the state.

        Args:
            key: Dot-separated path (e.g. 'server.dns.last_update.ip')
            default: Default value

        Returns:
            Value or default
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
        Set a value in the state.

        Args:
            key: Dot-separated path (e.g. 'server.dns.last_update.ip')
            value: Value to set
            save: Whether to persist immediately
        """
        parts = key.split(".")
        current = self._state

        # Navigate/create structure
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]

        # Set value
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
        Update the DNS state.

        Args:
            ip: Detected public IP
            domain: Updated domain
            records: List of updated records
            status: Status ('success', 'error', 'unchanged')
            message: Descriptive message
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
        logger.debug(f"📝 DNS state updated: {status}")

    def get_dns_state(self) -> Dict[str, Any]:
        """Return the current DNS state."""
        return self.get("server.dns", {})

    def get_last_dns_ip(self) -> Optional[str]:
        """Return the last known DNS IP (for fallback)."""
        return self.get("server.dns.last_update.ip")

    def get_last_dns_update_time(self) -> Optional[int]:
        """Return the timestamp of the last DNS update."""
        return self.get("server.dns.last_update.timestamp")

    def is_job_enabled(self, job_id: str) -> bool:
        """Check whether a job is enabled."""
        return self.get(f"daemon.jobs.{job_id}.enabled", True)

    def set_job_enabled(self, job_id: str, enabled: bool) -> None:
        """Enable or disable a job."""
        self.set(f"daemon.jobs.{job_id}.enabled", enabled)

    def get_job_config(self, job_id: str) -> Dict[str, Any]:
        """Return the configuration for a job."""
        return self.get(f"daemon.jobs.{job_id}", {})

    def set_job_config(self, job_id: str, config: Dict[str, Any]) -> None:
        """Set the configuration for a job."""
        self.set(f"daemon.jobs.{job_id}", config)

    def get_all_jobs_config(self) -> Dict[str, Any]:
        """Return the configuration of all jobs."""
        return self.get("daemon.jobs", {})

    def get_jobs_config(self) -> Dict[str, Any]:
        """Return the full jobs configuration."""
        cfg = self.get("daemon.jobs", {})
        return cfg if isinstance(cfg, dict) else {}

    def update_job(self, job_id: str, config: Dict[str, Any]) -> None:
        """Update/create a job configuration and persist the state."""
        jobs = self.get_jobs_config()
        jobs[job_id] = config
        self.set("daemon.jobs", jobs)

    def reset_jobs_defaults(self) -> None:
        """Reset the jobs configuration to the defaults."""
        from hms.lib.jobs_defaults import get_default_jobs

        self.set("daemon.jobs", get_default_jobs())


@deprecated("State will be removed")
def get_state_manager() -> StateManager:
    """Factory function to obtain the state manager."""
    return StateManager()
