"""Secrets manager backed by OneDrive (on-demand download, in-memory cache)."""

from __future__ import annotations

from pathlib import Path
import time
import yaml
import requests
from msal import ConfidentialClientApplication

from hms.lib.paths import get_config_root


class SecretsManager:
    """Loads secrets from OneDrive with an in-memory cache (TTL 5 minutes)."""

    def __init__(self, ttl_seconds: int = 300) -> None:
        self._cache: dict[str, tuple[dict, float]] = {}
        self._ttl = ttl_seconds
        self._access_token: str | None = None
        self._access_token_expiry: float = 0
        self._onedrive_config = self._load_onedrive_config()

    def fetch_platform_secrets_as_dict(self) -> dict:
        """Download secrets/platform.yml from OneDrive (cached)."""
        return self._get_cached(
            key="platform",
            loader=lambda: self._download_and_parse(f"{self._remote_base}/platform.yml"),
        )

    def fetch_stack_secrets_as_dict(self, stack_name: str) -> dict:
        """Download secrets/stacks/<stack>.yml from OneDrive (cached). Returns {} if not found."""
        return self._get_cached(
            key=f"stack:{stack_name}",
            loader=lambda: self._download_and_parse(
                f"{self._remote_base}/stacks/{stack_name}.yml",
                default={}
            ),
        )

    def clear_cache(self) -> None:
        """Clear the secrets cache."""
        self._cache.clear()

    # ------ Internal ------

    def _get_cached(self, key: str, loader) -> dict:
        now = time.time()
        if key in self._cache:
            data, ts = self._cache[key]
            if now - ts < self._ttl:
                return data
        data = loader()
        self._cache[key] = (data, now)
        return data

    def _download_and_parse(self, remote_path: str, default: dict | None = None) -> dict:
        """Download YAML from OneDrive and parse it."""
        content = self._download_from_onedrive(remote_path)
        if content is None:
            return default if default is not None else {}
        return yaml.safe_load(content) or {}

    def _load_onedrive_config(self) -> dict:
        """Load config/onedrive.yml."""
        cfg_path = get_config_root() / "onedrive.yml"
        if not cfg_path.exists():
            raise FileNotFoundError(
                f"OneDrive config not found: {cfg_path}\n"
                f"Run 'cp config/templates/onedrive.yml.template config/onedrive.yml' first"
            )
        with open(cfg_path) as f:
            data = yaml.safe_load(f) or {}

        # Validate required fields
        for key in ["remote_path", "client_id", "tenant_id", "client_secret", "refresh_token"]:
            if key not in data or not data[key]:
                raise ValueError(
                    f"config/onedrive.yml incomplete: {key} missing or empty\n"
                    f"Run 'hms setup configure-onedrive' to fill it"
                )

        self._remote_base = data["remote_path"].rstrip("/")
        return data

    def _get_access_token(self) -> str:
        """Obtain an access_token using refresh_token (cached until expiry)."""
        now = time.time()
        if self._access_token and now < self._access_token_expiry:
            return self._access_token

        app = ConfidentialClientApplication(
            client_id=self._onedrive_config["client_id"],
            client_credential=self._onedrive_config["client_secret"],
            authority=f"https://login.microsoftonline.com/{self._onedrive_config['tenant_id']}"
        )

        result = app.acquire_token_by_refresh_token(
            self._onedrive_config["refresh_token"],
            scopes=["https://graph.microsoft.com/.default"]
        )

        if "access_token" not in result:
            raise RuntimeError(
                f"Failed to get access token: {result.get('error_description', 'Unknown')}"
            )

        self._access_token = result["access_token"]
        self._access_token_expiry = now + 3300  # Cache for 55 min
        return self._access_token

    def _download_from_onedrive(self, remote_path: str) -> str | None:
        """Download a file from OneDrive via Graph API. Returns None on 404."""
        try:
            token = self._get_access_token()
        except RuntimeError as e:
            raise RuntimeError(f"Cannot authenticate with OneDrive: {e}")

        url = f"https://graph.microsoft.com/v1.0/me/drive/root:{remote_path}:/content"
        headers = {"Authorization": f"Bearer {token}"}

        try:
            resp = requests.get(url, headers=headers, timeout=10)
            if resp.status_code == 404:
                return None
            if resp.status_code != 200:
                raise RuntimeError(f"Graph API {resp.status_code}: {resp.text}")
            return resp.text
        except requests.RequestException as e:
            raise RuntimeError(f"Download failed: {e}")



