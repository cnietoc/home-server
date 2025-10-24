#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/common/env-loader.sh"

# Colores para logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Verificar si rclone está instalado
check_rclone() {
    if command -v rclone >/dev/null 2>&1; then
        local version
        version=$(rclone version | head -n1)
        log "rclone ya está instalado: $version"
        return 0
    else
        return 1
    fi
}

# Instalar rclone (Linux)
install_rclone() {
    log "🔧 Instalando rclone..."

    # Verificar que estamos en Linux
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "Este script solo funciona en Linux"
        exit 1
    fi

    # Instalar según el gestor de paquetes disponible
    if command -v apt-get >/dev/null 2>&1; then
        log "Instalando rclone via apt..."
        sudo apt-get update
        sudo apt-get install -y rclone
    elif command -v yum >/dev/null 2>&1; then
        log "Instalando rclone via yum..."
        sudo yum install -y rclone
    elif command -v dnf >/dev/null 2>&1; then
        log "Instalando rclone via dnf..."
        sudo dnf install -y rclone
    else
        warn "Gestor de paquetes no detectado. Instalando via script oficial..."
        curl https://rclone.org/install.sh | sudo bash
    fi

    if check_rclone; then
        log "✅ rclone instalado correctamente"
    else
        error "❌ Error al instalar rclone"
        exit 1
    fi
}

# Configurar OneDrive
configure_onedrive() {
    # Verificar si ya existe una configuración de OneDrive
    if rclone listremotes 2>/dev/null | grep -q "onedrive:"; then
        info "OneDrive ya configurado. ¿Reconfigurar? (y/n)"
        read -r reconfigure

        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            log "✅ Usando configuración existente"
            return 0
        fi
    fi

    log "🔧 Configurando OneDrive..."
    rclone config

    log "✅ OneDrive configurado"
}



# Configurar montaje automático al arranque (Linux)
setup_auto_mount() {
    log "🔧 Configurando montaje automático al arranque..."

    # Verificar que estamos en Linux
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "Este script solo funciona en Linux"
        return 1
    fi

    # Crear directorio de montaje si no existe
    local mount_dir="$HOME/OneDrive"
    mkdir -p "$mount_dir"

    setup_systemd_service "$mount_dir"
}

# Crear servicio systemd para Linux
setup_systemd_service() {
    local mount_dir="$1"
    local service_file="$HOME/.config/systemd/user/onedrive-rclone.service"

    # Verificar si el servicio ya existe
    if [[ -f "$service_file" ]]; then
        info "Servicio systemd ya existe, verificando configuración..."

        # Verificar si está habilitado
        if systemctl --user is-enabled onedrive-rclone.service >/dev/null 2>&1; then
            info "Servicio ya está habilitado"
        else
            log "Habilitando servicio existente..."
            systemctl --user enable onedrive-rclone.service
        fi

        # Verificar si está corriendo
        if systemctl --user is-active onedrive-rclone.service >/dev/null 2>&1; then
            info "Servicio ya está activo"
        else
            info "Para iniciar el servicio: systemctl --user start onedrive-rclone.service"
        fi

        return 0
    fi

    log "📝 Creando servicio systemd..."

    # Crear directorio para servicios de usuario
    mkdir -p "$HOME/.config/systemd/user"

    cat > "$service_file" << EOF
[Unit]
Description=OneDrive (rclone)
AssertPathIsDirectory=$mount_dir
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStartPre=/bin/mkdir -p $mount_dir
ExecStart=/usr/bin/rclone mount onedrive: $mount_dir \\
    --config=%h/.config/rclone/rclone.conf \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-age 100h \\
    --vfs-cache-max-size 10G \\
    --vfs-cache-poll-interval 15s \\
    --dir-cache-time 5m \\
    --poll-interval 15s \\
    --umask 002 \\
    --allow-other
ExecStop=/bin/fusermount -u $mount_dir
Restart=always
RestartSec=10
Environment=PATH=/usr/bin:/bin

[Install]
WantedBy=default.target
EOF

    # Habilitar el servicio
    systemctl --user daemon-reload
    systemctl --user enable onedrive-rclone.service

    log "✅ Servicio systemd creado y habilitado"
    info "Para iniciar ahora: systemctl --user start onedrive-rclone.service"
    info "Para ver logs: journalctl --user -u onedrive-rclone.service -f"
}



# Mostrar resumen final
show_summary() {
    echo
    log "🎉 Instalación y configuración de OneDrive completada!"
    echo
    info "📋 Para usar OneDrive manualmente:"
    info "  • Montar: rclone mount onedrive: ~/OneDrive --daemon --vfs-cache-mode writes"
    info "  • Desmontar: fusermount -u ~/OneDrive"
    info "  • Ver estado: rclone about onedrive:"
    info "  • Gestionar: rclone config"
    echo
    info "🚀 Servicio systemd configurado:"
    info "  • Iniciar servicio: systemctl --user start onedrive-rclone.service"
    info "  • Ver estado: systemctl --user status onedrive-rclone.service"
    info "  • Ver logs: journalctl --user -u onedrive-rclone.service -f"
    info "  • Deshabilitar: systemctl --user disable onedrive-rclone.service"
    echo
}

# Función principal
main() {
    log "🚀 Instalando rclone y configurando OneDrive..."

    # Verificar/instalar rclone
    if ! check_rclone; then
        install_rclone
    fi

    # Configurar OneDrive
    info "¿Quieres configurar OneDrive ahora? (y/n)"
    read -r configure_now

    if [[ "$configure_now" =~ ^[Yy]$ ]]; then
        configure_onedrive

        # Preguntar sobre montaje automático
        echo
        info "¿Quieres que OneDrive se monte automáticamente al arrancar el sistema? (y/n)"
        read -r auto_mount

        if [[ "$auto_mount" =~ ^[Yy]$ ]]; then
            setup_auto_mount
        else
            info "Puedes configurar el montaje automático más tarde ejecutando este script de nuevo"
        fi

        show_summary
    else
        log "✅ rclone instalado. Configura OneDrive más tarde con: rclone config"
    fi
}

# Ejecutar función principal
main "$@"
