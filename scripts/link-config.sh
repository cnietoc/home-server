#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
TEMPLATES_DIR="$CONFIG_DIR/templates"
PRIVATE_LINK="$CONFIG_DIR/private"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

link_config() {
    if [[ $# -ne 1 ]]; then
        echo "Uso: $0 <ruta-absoluta-a-configuracion-privada>"
        echo ""
        echo "Ejemplos:"
        echo "  $0 /home/usuario/home-server-config"
        echo "  $0 ~/Documents/home-server-envs"
        echo "  $0 /mnt/encrypted/config"
        exit 1
    fi

    local config_path="$1"
    config_path="${config_path/#\~/$HOME}"

    # Convertir a ruta absoluta
    if [[ ! "$config_path" = /* ]]; then
        config_path="$(cd "$(dirname "$config_path")" && pwd)/$(basename "$config_path")"
    fi

    # Verificar que existe
    if [[ ! -d "$config_path" ]]; then
        log "❌ La carpeta no existe: $config_path"
        log "Crea la carpeta primero: mkdir -p '$config_path'"
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
    ln -sf "$config_path" "$PRIVATE_LINK"
    log "✅ Enlace creado: config/private -> $config_path"

    # Verificar
    if [[ -d "$PRIVATE_LINK" ]]; then
        log "✅ Enlace verificado"
    else
        log "❌ El enlace no funciona"
        exit 1
    fi

    # Copiar plantillas si no existen
    copy_templates_if_needed "$config_path"
    log "🎉 Configuración completada"
}

copy_templates_if_needed() {
    local config_path="$1"
    local copied=0

    log "Verificando plantillas..."

    # Verificar que el directorio de plantillas existe
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        log "❌ Directorio de plantillas no encontrado: $TEMPLATES_DIR"
        return 1
    fi

    # Copiar todas las plantillas directamente en la raíz
    shopt -s nullglob  # Hacer que los globs que no coinciden se expandan a nada
    for template in "$TEMPLATES_DIR"/*.env.template; do
        local filename="$(basename "$template" .template)"
        local target="$config_path/$filename"

        if [[ ! -f "$target" ]]; then
            cp "$template" "$target"
            log "✅ Copiado: $filename"
            ((copied++))
        else
            log "📄 Ya existe: $filename"
        fi
    done
    shopt -u nullglob  # Restaurar comportamiento normal

    if [[ $copied -gt 0 ]]; then
        log "📝 Se copiaron $copied archivos de configuración. Edítalos antes de usar los scripts."
    else
        log "📝 Todos los archivos de configuración ya existen."
    fi
}

link_config "$@"
