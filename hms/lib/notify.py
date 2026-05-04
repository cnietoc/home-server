"""
Notifications for HMS via Apprise.
Only notifies if global.notification_url is configured.
"""

import logging

logger = logging.getLogger(__name__)


def send(title: str, body: str) -> None:
    """Send a notification if a URL is configured. Fails silently."""
    try:
        from hms.lib.config import config_manager

        url = config_manager.get_config_value("global.notification_url", "")
        if not url or url == "__REQUIRED__":
            return

        import apprise

        ap = apprise.Apprise()
        ap.add(url)
        ap.notify(title=title, body=body)
    except Exception as e:
        logger.warning(f"⚠️ Notification failed: {e}")
