"""
Notificaciones para HMS via Apprise.
Solo notifica si global.notification_url está configurado.
"""

import logging

logger = logging.getLogger(__name__)


def send(title: str, body: str) -> None:
    """Enviar notificación si hay URL configurada. Falla silenciosamente."""
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
        logger.warning(f"⚠️ Notificación fallida: {e}")
