#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
TEMPLATES_DIR="$CONFIG_DIR/templates"
PRIVATE_LINK="$CONFIG_DIR/private"
PRIVATE_LINK="$CONFIG_DIR/private"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

link_secrets() {
    if [[ $# -ne 1 ]]; then
        echo "Uso: $0 <ruta-absoluta-a-secretos>"
        echo ""
        echo "Ejemplos:"
        echo "  $0 /home/usuario/secrets"
        echo "  $0 ~/Documents/home-server-secrets"
        echo "  $0 /mnt/encrypted/secrets"
        exit 1
    fi

    local secrets_path="$1"
    secrets_path="${secrets_path/#\~/$HOME}"

    # Convertir a ruta absoluta
    if [[ ! "$secrets_path" = /* ]]; then
        secrets_path="$(cd "$(dirname "$secrets_path")" && pwd)/$(basename "$secrets_path")"
    fi

    # Verificar que existe
    if [[ ! -d "$secrets_path" ]]; then
        log "❌ La carpeta no existe: $secrets_path"
        log "Crea la carpeta primero: mkdir -p '$secrets_path'"
        exit 1
    fi

    # Eliminar enlace existente
    if [[ -L "$PRIVATE_LINK" ]]; then
        log "Eliminando enlace existente..."
        rm "$PRIVATE_LINK"
    elif [[ -e "$PRIVATE_LINK" ]]; then
        log "❌ Existe un archivo/carpeta en $PRIVATE_LINK"
        log "Elimínalo: rm -rf '$PRIVATE_LINK'"
        exit 1
    fi

    # Crear enlace
    ln -sf "$secrets_path" "$PRIVATE_LINK"
    log "✅ Enlace creado: config/private -> $secrets_path"

    # Verificar
    if [[ -d "$PRIVATE_LINK" ]]; then
        log "✅ Enlace verificado"
    else
        log "❌ El enlace no funciona"
        exit 1
    fi

    # Copiar plantillas si no existen
    copy_templates_if_needed "$secrets_path"
    log "🎉 Configuración completada"
}

copy_templates_if_needed() {
    local secrets_path="$1"
    local copied=0

    log "Verificando plantillas..."

    # Copiar todas las plantillas directamente en la raíz
    for template in "$TEMPLATES_DIR"/*.env.template; do
        if [[ -f "$template" ]]; then
            local filename="$(basename "$template" .template)"
            local target="$secrets_path/$filename"

            if [[ ! -f "$target" ]]; then
                cp "$template" "$target"
                log "✅ Copiado: $filename"
                ((copied++))
            fi
        fi
    done

    if [[ $copied -gt 0 ]]; then
        log "📝 Se copiaron $copied archivos. Edítalos antes de usar los scripts."
    else
        log "📝 Todos los archivos ya existen."
    fi
}

link_secrets "$@"
