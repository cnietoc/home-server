#!/usr/bin/env bash
set -euo pipefail

# Script para deployment automático desde GitHub Actions
# Este script actúa como wrapper del deploy.sh principal con logging mejorado

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/deployment.log"

# Función de logging con timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Función para enviar notificación (opcional)
send_notification() {
    local status="$1"
    local message="$2"

    # Si tienes configurado Telegram o webhook, puedes añadir notificaciones aquí
    # Ejemplo con curl a un webhook:
    # curl -s -X POST "$WEBHOOK_URL" -d "{"status":"$status","message":"$message"}" || true

    log_with_timestamp "📱 Notification: $status - $message"
}

# Verificar que estamos en el directorio correcto
if [[ ! -f "$SCRIPT_DIR/deploy.sh" ]]; then
    log_with_timestamp "❌ Error: deploy.sh not found in $SCRIPT_DIR"
    exit 1
fi

log_with_timestamp "🚀 Starting automatic deployment from GitHub Actions"
log_with_timestamp "📂 Working directory: $PROJECT_ROOT"
log_with_timestamp "🌿 Git branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
log_with_timestamp "📝 Git commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')"

# Verificar que el enlace de configuración privada existe
if [[ ! -L "$PROJECT_ROOT/config/private" ]]; then
    log_with_timestamp "⚠️ Warning: config/private symlink not found"
    log_with_timestamp "   Make sure you have configured: ./scripts/link-config.sh"
fi

# Parsear argumentos
DEPLOY_ARGS=()
FORCE_DEPLOY=false
RECREATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DEPLOY=true
            DEPLOY_ARGS+=("--force")
            shift
            ;;
        --recreate)
            RECREATE=true
            DEPLOY_ARGS+=("--recreate")
            shift
            ;;
        --verbose)
            DEPLOY_ARGS+=("--verbose")
            shift
            ;;
        *)
            DEPLOY_ARGS+=("$1")
            shift
            ;;
    esac
done

# Mostrar configuración del deployment
log_with_timestamp "⚙️ Deployment configuration:"
log_with_timestamp "   Force deploy: $FORCE_DEPLOY"
log_with_timestamp "   Recreate containers: $RECREATE"
log_with_timestamp "   Arguments: ${DEPLOY_ARGS[*]:-none}"

# Ejecutar deployment
log_with_timestamp "🎯 Executing deployment script..."
if "$SCRIPT_DIR/deploy.sh" "${DEPLOY_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"; then
    log_with_timestamp "✅ Deployment completed successfully"
    send_notification "success" "Home server deployment completed successfully"

    # Mostrar URLs de acceso
    if [[ -f "$PROJECT_ROOT/config/private/common.env" ]]; then
        source "$PROJECT_ROOT/config/private/common.env" 2>/dev/null || true
        if [[ -n "${BASE_DOMAIN:-}" ]]; then
            log_with_timestamp "🌐 Services available at:"
            log_with_timestamp "   🔀 Traefik: https://traefik.$BASE_DOMAIN"
            log_with_timestamp "   👋 Hello World: https://hello.$BASE_DOMAIN"
        fi
    fi

    exit 0
else
    log_with_timestamp "❌ Deployment failed"
    send_notification "error" "Home server deployment failed"

    # Mostrar últimas líneas del log para debugging
    log_with_timestamp "📋 Last 10 lines of deployment log:"
    tail -10 "$LOG_FILE" | sed 's/^/   /'

    exit 1
fi
