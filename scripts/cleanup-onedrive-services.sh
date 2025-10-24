#!/usr/bin/env bash
set -euo pipefail

# Colores para logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  $1${NC}"
}

cleanup_user_service() {
    log "🧹 Limpiando servicios de usuario previos..."

    local current_user=$(whoami)
    local user_service_file="$HOME/.config/systemd/user/onedrive-rclone.service"

    # Detener y deshabilitar servicio de usuario si existe
    if [[ -f "$user_service_file" ]]; then
        warn "Encontrado servicio de usuario, eliminando..."

        # Intentar detener el servicio
        if systemctl --user is-active onedrive-rclone.service >/dev/null 2>&1; then
            log "Deteniendo servicio de usuario..."
            systemctl --user stop onedrive-rclone.service
        fi

        # Deshabilitar servicio
        if systemctl --user is-enabled onedrive-rclone.service >/dev/null 2>&1; then
            log "Deshabilitando servicio de usuario..."
            systemctl --user disable onedrive-rclone.service
        fi

        # Eliminar archivo de servicio
        rm -f "$user_service_file"
        log "✅ Archivo de servicio de usuario eliminado"

        # Recargar daemon de usuario
        systemctl --user daemon-reload
        log "✅ Daemon de usuario recargado"
    else
        log "✅ No se encontró servicio de usuario previo"
    fi

    # Verificar si hay procesos rclone corriendo del usuario
    local rclone_pids
    rclone_pids=$(pgrep -u "$current_user" rclone 2>/dev/null || true)

    if [[ -n "$rclone_pids" ]]; then
        warn "Encontrados procesos rclone ejecutándose:"
        ps -p $rclone_pids -o pid,ppid,cmd

        info "¿Quieres terminar estos procesos? (y/n)"
        read -r kill_processes

        if [[ "$kill_processes" =~ ^[Yy]$ ]]; then
            log "Terminando procesos rclone..."
            kill $rclone_pids
            sleep 2

            # Verificar si siguen corriendo y usar kill -9 si es necesario
            local remaining_pids
            remaining_pids=$(pgrep -u "$current_user" rclone 2>/dev/null || true)
            if [[ -n "$remaining_pids" ]]; then
                warn "Forzando terminación de procesos restantes..."
                kill -9 $remaining_pids
            fi
            log "✅ Procesos rclone terminados"
        fi
    fi

    # Desmontar OneDrive si está montado
    local mount_dir="$HOME/OneDrive"
    if mountpoint -q "$mount_dir" 2>/dev/null; then
        warn "OneDrive está montado, desmontando..."
        if fusermount -u "$mount_dir"; then
            log "✅ OneDrive desmontado"
        else
            warn "Error al desmontar, intentando con sudo..."
            sudo umount "$mount_dir" 2>/dev/null || true
        fi
    fi

    log "🎉 Limpieza de servicios de usuario completada"
    echo
    info "Ahora puedes ejecutar el script principal para crear el servicio de sistema:"
    info "./scripts/install-onedrive.sh"
}

# Verificar estado actual
check_current_status() {
    log "🔍 Verificando estado actual..."
    echo

    local current_user=$(whoami)

    # Verificar servicio de usuario
    local user_service_file="$HOME/.config/systemd/user/onedrive-rclone.service"
    if [[ -f "$user_service_file" ]]; then
        warn "❌ Servicio de usuario encontrado: $user_service_file"
        if systemctl --user is-active onedrive-rclone.service >/dev/null 2>&1; then
            error "  └─ Servicio ACTIVO"
        else
            info "  └─ Servicio inactivo"
        fi
    else
        log "✅ No hay servicio de usuario"
    fi

    # Verificar servicio de sistema
    local system_service_file="/etc/systemd/system/onedrive-rclone@.service"
    if [[ -f "$system_service_file" ]]; then
        log "✅ Servicio de sistema encontrado: $system_service_file"
        if sudo systemctl is-active "onedrive-rclone@${current_user}.service" >/dev/null 2>&1; then
            log "  └─ Servicio ACTIVO"
        else
            info "  └─ Servicio inactivo"
        fi
    else
        warn "❌ No hay servicio de sistema"
    fi

    # Verificar procesos rclone
    local rclone_count
    rclone_count=$(pgrep -u "$current_user" -c rclone 2>/dev/null || echo "0")
    if [[ "$rclone_count" -gt 0 ]]; then
        warn "❌ $rclone_count procesos rclone ejecutándose"
    else
        log "✅ No hay procesos rclone ejecutándose"
    fi

    # Verificar montaje
    local mount_dir="$HOME/OneDrive"
    if mountpoint -q "$mount_dir" 2>/dev/null; then
        warn "❌ OneDrive está montado en $mount_dir"
    else
        log "✅ OneDrive no está montado"
    fi

    echo
}

main() {
    if [[ "${1:-}" == "status" ]]; then
        check_current_status
        return
    fi

    log "🚀 Script de limpieza de servicios OneDrive"
    echo

    check_current_status

    info "¿Proceder con la limpieza de servicios de usuario? (y/n)"
    read -r proceed

    if [[ "$proceed" =~ ^[Yy]$ ]]; then
        cleanup_user_service
        echo
        check_current_status
    else
        info "Limpieza cancelada"
    fi
}

main "$@"
