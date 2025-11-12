#!/usr/bin/env bash
# set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Detectar tipo de enlace basado en el parámetro
LINK_TYPE="${1:-config}"
[[ $# -gt 0 ]] && shift

# Configurar rutas según el tipo
case "$LINK_TYPE" in
    "config")
        CONFIG_DIR="$PROJECT_ROOT/config"
        TEMPLATES_DIR="$CONFIG_DIR/templates"
        PRIVATE_LINK="$CONFIG_DIR/private"
        LINK_DESCRIPTION="configuración privada"
        ;;
    "backups")
        DATA_DIR="$PROJECT_ROOT/data"
        PRIVATE_LINK="$DATA_DIR/backups"
        LINK_DESCRIPTION="backups"
        TEMPLATES_DIR=""  # No hay templates para backups
        ;;
    *)
        echo "❌ Tipo de enlace no válido: $LINK_TYPE"
        echo ""
        echo "Tipos válidos:"
        echo "  config   - Enlazar directorio de configuración privada (.env files)"
        echo "  backups  - Enlazar directorio de backups"
        echo ""
        echo "Uso:"
        echo "  $0 config <ruta-absoluta-a-configuracion>"
        echo "  $0 backups <ruta-absoluta-a-backups>"
        echo ""
        echo "Ejemplos:"
        echo "  $0 config ~/config/home-server"
        echo "  $0 backups /mnt/backup-drive/home-server-backups"
        exit 1
        ;;
esac

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

link_directory() {
    if [[ $# -ne 1 ]]; then
        echo "Uso: $0 $LINK_TYPE <ruta-absoluta-a-$LINK_DESCRIPTION>"
        echo ""
        echo "Tipos de enlace disponibles:"
        echo "  config   - Enlazar directorio de configuración privada (.env files)"
        echo "  backups  - Enlazar directorio de backups"
        echo ""
        echo "Ejemplos para $LINK_TYPE:"
        case "$LINK_TYPE" in
            "config")
                echo "  $0 config /home/usuario/home-server-config"
                echo "  $0 config ~/Documents/home-server-envs"
                echo "  $0 config /mnt/encrypted/config"
                ;;
            "backups")
                echo "  $0 backups /mnt/backup-drive/home-server-backups"
                echo "  $0 backups ~/Backups/home-server"
                echo "  $0 backups /backup/storage/home-server"
                ;;
        esac
        exit 1
    fi

    local target_path="$1"
    target_path="${target_path/#\~/$HOME}"

    # Convertir a ruta absoluta
    if [[ ! "$target_path" = /* ]]; then
        target_path="$(cd "$(dirname "$target_path")" && pwd)/$(basename "$target_path")"
    fi

    # Verificar que existe
    if [[ ! -d "$target_path" ]]; then
        log "❌ La carpeta no existe: $target_path"
        log "Crea la carpeta primero: mkdir -p '$target_path'"
        exit 1
    fi

    # Crear directorio padre si es necesario (para backups)
    if [[ "$LINK_TYPE" == "backups" ]]; then
        mkdir -p "$(dirname "$PRIVATE_LINK")"
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
    ln -sf "$target_path" "$PRIVATE_LINK"
    log "✅ Enlace creado: $(basename "$(dirname "$PRIVATE_LINK")")/$(basename "$PRIVATE_LINK") -> $target_path"

    # Verificar
    if [[ -d "$PRIVATE_LINK" ]]; then
        log "✅ Enlace verificado"
    else
        log "❌ El enlace no funciona"
        exit 1
    fi

    # Copiar plantillas si es para config
    if [[ "$LINK_TYPE" == "config" ]]; then
        copy_templates_if_needed "$target_path"
    fi

    log "🎉 Configuración de $LINK_TYPE completada"
}

copy_templates_if_needed() {
    local target_path="$1"
    local copied=0

    # Solo para config, no para backups
    if [[ "$LINK_TYPE" != "config" || -z "$TEMPLATES_DIR" ]]; then
        return 0
    fi

    log "Verificando plantillas..."

    # Verificar que el directorio de plantillas existe
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        log "❌ Directorio de plantillas no encontrado: $TEMPLATES_DIR"
        return 1
    fi

    # Copiar todas las plantillas
    while IFS= read -r -d '' template; do
        local filename
        filename="$(basename "$template" .template)"
        local target="$target_path/$filename"

        if [[ ! -f "$target" ]]; then
            if cp "$template" "$target" 2>/dev/null; then
                log "✅ Copiado: $filename"
                ((copied++))
            else
                log "❌ Error copiando: $filename"
            fi
        fi
    done < <(find "$TEMPLATES_DIR" -name "*.env.template" -print0 2>/dev/null)


    if [[ $copied -gt 0 ]]; then
        log "📝 Se copiaron $copied archivos de configuración. Edítalos antes de usar los scripts."
    else
        log "📝 Todos los archivos de configuración ya existen."
    fi
}

link_directory "$@"
