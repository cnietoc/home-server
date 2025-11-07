#!/bin/bash

# Script para gestionar NFS shares basado en la configuración de stacks.yml
# Autor: Home Server
# Fecha: $(date +%Y-%m-%d)

set -euo pipefail

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STACKS_CONFIG="$PROJECT_ROOT/config/stacks.yml"
EXPORTS_FILE="/etc/exports"
LOG_FILE="$PROJECT_ROOT/data/logs/nfs.log"

# Cargar utilidades comunes
source "$SCRIPT_DIR/common/env-loader.sh"

# Logging
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# Función para verificar si somos root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script necesita ejecutarse como root para gestionar NFS"
        echo "Uso: sudo $0 [setup|status|remove]"
        exit 1
    fi
}

# Función para instalar NFS server
install_nfs() {
    log_info "Verificando instalación de NFS server..."

    if ! command -v nfs-kernel-server &> /dev/null; then
        log_info "Instalando NFS server..."
        apt-get update
        apt-get install -y nfs-kernel-server nfs-common
        systemctl enable nfs-kernel-server
    else
        log_info "NFS server ya está instalado"
    fi
}

# Función para extraer configuración NFS del stacks.yml
extract_nfs_config() {
    if ! command -v yq &> /dev/null; then
        log_error "yq no está instalado. Instálalo con: sudo apt-get install yq"
        exit 1
    fi

    # Verificar si el archivo existe
    if [[ ! -f "$STACKS_CONFIG" ]]; then
        log_error "No se encontró el archivo de configuración: $STACKS_CONFIG"
        exit 1
    fi

    # Extraer stacks que tienen configuración NFS
    yq eval '.stacks | to_entries | .[] | select(.value.nfs_shares) | .key' "$STACKS_CONFIG" 2>/dev/null || true
}

# Función para generar configuración de exports
generate_exports() {
    local exports_content="# NFS exports generados automáticamente por nfs-manager.sh\n"
    exports_content+="# Generado el: $(date)\n"
    exports_content+="# NO EDITAR MANUALMENTE - será sobrescrito\n\n"

    local stacks_with_nfs
    stacks_with_nfs=$(extract_nfs_config)

    if [[ -z "$stacks_with_nfs" ]]; then
        log_info "No se encontraron stacks con configuración NFS"
        return
    fi

    while IFS= read -r stack_name; do
        [[ -z "$stack_name" ]] && continue

        exports_content+="\n# Stack: $stack_name\n"

        local shares
        shares=$(yq eval ".stacks.$stack_name.nfs_shares | to_entries | .[] | .key" "$STACKS_CONFIG" 2>/dev/null || true)

        while IFS= read -r share_name; do
            [[ -z "$share_name" ]] && continue

            local path permissions description exposed_path
            path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.path" "$STACKS_CONFIG")
            permissions=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.permissions" "$STACKS_CONFIG")
            description=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.description" "$STACKS_CONFIG")

            # Usar exposed_path si está definido, sino usar path
            exposed_path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.exposed_path // \"\"" "$STACKS_CONFIG")
            if [[ -z "$exposed_path" || "$exposed_path" == "null" ]]; then
                exposed_path="$path"
            fi

            # Configurar permisos NFS
            local nfs_opts
            case "$permissions" in
                "rw") nfs_opts="rw,sync,no_subtree_check,no_root_squash" ;;
                "ro") nfs_opts="ro,sync,no_subtree_check,no_root_squash" ;;
                *) nfs_opts="ro,sync,no_subtree_check,no_root_squash" ;;
            esac

            exports_content+="# $description\n"
            exports_content+="$exposed_path *(${nfs_opts})\n"

        done <<< "$shares"

    done <<< "$stacks_with_nfs"

    echo -e "$exports_content" > "$EXPORTS_FILE"
    log_info "Archivo $EXPORTS_FILE generado"
}

# Función para crear directorios NFS
create_nfs_directories() {
    log_info "Creando directorios NFS..."

    local stacks_with_nfs
    stacks_with_nfs=$(extract_nfs_config)

    [[ -z "$stacks_with_nfs" ]] && return

    while IFS= read -r stack_name; do
        [[ -z "$stack_name" ]] && continue

        local shares
        shares=$(yq eval ".stacks.$stack_name.nfs_shares | to_entries | .[] | .key" "$STACKS_CONFIG" 2>/dev/null || true)

        while IFS= read -r share_name; do
            [[ -z "$share_name" ]] && continue

            local path exposed_path
            path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.path" "$STACKS_CONFIG")
            exposed_path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.exposed_path // \"\"" "$STACKS_CONFIG")

            if [[ -z "$exposed_path" || "$exposed_path" == "null" ]]; then
                exposed_path="$path"
            fi

            # Crear directorio real si no existe
            if [[ ! -d "$path" ]]; then
                mkdir -p "$path"
                log_info "📁 Creado directorio real: $path"
            else
                log_info "📁 Directorio real ya existe: $path"
            fi

            # Si exposed_path es diferente, crear bind mount
            if [[ "$exposed_path" != "$path" ]]; then
                # Crear directorio para exposed_path si no existe
                if [[ ! -d "$exposed_path" ]]; then
                    mkdir -p "$exposed_path"
                    log_info "📁 Creado directorio expuesto: $exposed_path"
                fi

                # Verificar si ya existe el bind mount
                if ! mountpoint -q "$exposed_path"; then
                    mount --bind "$path" "$exposed_path"
                    log_info "🔗 Creado bind mount: $path -> $exposed_path"
                else
                    log_info "🔗 Bind mount ya existe: $exposed_path"
                fi
            fi

        done <<< "$shares"

    done <<< "$stacks_with_nfs"
}

# Función para gestionar bind mounts en /etc/fstab para persistencia
setup_bind_mounts_fstab() {
    log_info "Configurando bind mounts en /etc/fstab..."

    # Crear backup de fstab
    cp /etc/fstab /etc/fstab.backup.nfs-manager

    # Remover entradas anteriores de NFS manager
    sed -i '/# NFS Manager bind mounts/,/# End NFS Manager bind mounts/d' /etc/fstab

    local stacks_with_nfs
    stacks_with_nfs=$(extract_nfs_config)

    [[ -z "$stacks_with_nfs" ]] && return

    local bind_mounts_needed=false

    while IFS= read -r stack_name; do
        [[ -z "$stack_name" ]] && continue

        local shares
        shares=$(yq eval ".stacks.$stack_name.nfs_shares | to_entries | .[] | .key" "$STACKS_CONFIG" 2>/dev/null || true)

        while IFS= read -r share_name; do
            [[ -z "$share_name" ]] && continue

            local path exposed_path
            path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.path" "$STACKS_CONFIG")
            exposed_path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.exposed_path // \"\"" "$STACKS_CONFIG")

            if [[ -z "$exposed_path" || "$exposed_path" == "null" ]]; then
                exposed_path="$path"
            fi

            # Si necesitamos bind mount, añadirlo a fstab
            if [[ "$exposed_path" != "$path" ]]; then
                if [[ "$bind_mounts_needed" == false ]]; then
                    echo "" >> /etc/fstab
                    echo "# NFS Manager bind mounts" >> /etc/fstab
                    bind_mounts_needed=true
                fi
                echo "$path $exposed_path none bind 0 0" >> /etc/fstab
                log_info "📝 Añadido bind mount a fstab: $path -> $exposed_path"
            fi

        done <<< "$shares"

    done <<< "$stacks_with_nfs"

    if [[ "$bind_mounts_needed" == true ]]; then
        echo "# End NFS Manager bind mounts" >> /etc/fstab
    fi
}

# Función para configurar NFS
setup_nfs() {
    log_info "🚀 Configurando NFS..."

    install_nfs
    create_nfs_directories
    setup_bind_mounts_fstab
    generate_exports

    # Reiniciar servicios NFS
    log_info "Reiniciando servicios NFS..."
    systemctl restart nfs-kernel-server
    exportfs -ra

    log_success "✅ NFS configurado correctamente"
    show_nfs_status
}

# Función para mostrar estado de NFS
show_nfs_status() {
    echo ""
    echo "📋 Estado de compartidas NFS:"
    echo "=============================="

    local stacks_with_nfs
    stacks_with_nfs=$(extract_nfs_config)

    if [[ -z "$stacks_with_nfs" ]]; then
        echo "❌ No hay stacks con configuración NFS"
        return
    fi

    while IFS= read -r stack_name; do
        [[ -z "$stack_name" ]] && continue

        echo ""
        echo "🔗 Stack: $stack_name"

        local description
        description=$(yq eval ".stacks.$stack_name.description" "$STACKS_CONFIG")
        echo "   $description"

        local shares
        shares=$(yq eval ".stacks.$stack_name.nfs_shares | to_entries | .[] | .key" "$STACKS_CONFIG" 2>/dev/null || true)

        while IFS= read -r share_name; do
            [[ -z "$share_name" ]] && continue

            local path permissions description exposed_path
            path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.path" "$STACKS_CONFIG")
            permissions=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.permissions" "$STACKS_CONFIG")
            description=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.description" "$STACKS_CONFIG")

            # Usar exposed_path si está definido, sino usar path
            exposed_path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.exposed_path // \"\"" "$STACKS_CONFIG")
            if [[ -z "$exposed_path" || "$exposed_path" == "null" ]]; then
                exposed_path="$path"
            fi

            echo "   • $share_name: $exposed_path ($permissions)"
            if [[ "$exposed_path" != "$path" ]]; then
                echo "     └─ Ruta real: $path"
            fi
            echo "     $description"

        done <<< "$shares"

    done <<< "$stacks_with_nfs"

    echo ""
    echo "🌐 Exportaciones activas:"
    exportfs -v 2>/dev/null || echo "❌ No hay exportaciones activas"

    echo ""
    echo "📊 Estado del servicio:"
    systemctl status nfs-kernel-server --no-pager -l || true
}

# Función para remover configuración NFS
remove_nfs() {
    log_info "🗑️  Removiendo configuración NFS..."

    # Desmontar bind mounts
    local stacks_with_nfs
    stacks_with_nfs=$(extract_nfs_config)

    if [[ -n "$stacks_with_nfs" ]]; then
        while IFS= read -r stack_name; do
            [[ -z "$stack_name" ]] && continue

            local shares
            shares=$(yq eval ".stacks.$stack_name.nfs_shares | to_entries | .[] | .key" "$STACKS_CONFIG" 2>/dev/null || true)

            while IFS= read -r share_name; do
                [[ -z "$share_name" ]] && continue

                local path exposed_path
                path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.path" "$STACKS_CONFIG")
                exposed_path=$(yq eval ".stacks.$stack_name.nfs_shares.$share_name.exposed_path // \"\"" "$STACKS_CONFIG")

                if [[ -z "$exposed_path" || "$exposed_path" == "null" ]]; then
                    exposed_path="$path"
                fi

                # Desmontar bind mount si existe
                if [[ "$exposed_path" != "$path" ]] && mountpoint -q "$exposed_path"; then
                    umount "$exposed_path"
                    log_info "🔗 Desmontado bind mount: $exposed_path"
                fi

            done <<< "$shares"

        done <<< "$stacks_with_nfs"
    fi

    # Limpiar fstab
    if [[ -f /etc/fstab.backup.nfs-manager ]]; then
        sed -i '/# NFS Manager bind mounts/,/# End NFS Manager bind mounts/d' /etc/fstab
        log_info "📝 Limpiadas entradas de fstab"
    fi

    # Limpiar exports
    echo "# NFS exports" > "$EXPORTS_FILE"
    exportfs -ra
    systemctl stop nfs-kernel-server

    log_success "✅ Configuración NFS removida"
}

# Función para mostrar ayuda
show_help() {
    echo "NFS Manager - Gestión de compartidas NFS basado en stacks.yml"
    echo ""
    echo "Uso: sudo $0 [comando]"
    echo ""
    echo "Comandos:"
    echo "  setup     - Configurar NFS basado en stacks.yml"
    echo "  status    - Mostrar estado de las compartidas NFS"
    echo "  remove    - Remover configuración NFS"
    echo "  help      - Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  sudo $0 setup"
    echo "  sudo $0 status"
    echo ""
}

# Función principal
main() {
    # Crear directorio de logs si no existe
    mkdir -p "$(dirname "$LOG_FILE")"

    local command="${1:-}"

    case "$command" in
        "setup")
            check_root
            setup_nfs
            ;;
        "status")
            show_nfs_status
            ;;
        "remove")
            check_root
            remove_nfs
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            log_error "No se especificó comando"
            show_help
            exit 1
            ;;
        *)
            log_error "Comando desconocido: $command"
            show_help
            exit 1
            ;;
    esac
}

# Ejecutar función principal con todos los argumentos
main "$@"
