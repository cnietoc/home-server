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



# Configurar fuse para permitir allow_other
configure_fuse() {
    log "🔧 Configurando FUSE..."

    local fuse_conf="/etc/fuse.conf"

    # Verificar si fuse.conf existe y tiene user_allow_other
    if [[ -f "$fuse_conf" ]] && grep -q "^user_allow_other" "$fuse_conf"; then
        log "✅ FUSE ya configurado correctamente"
        return 0
    fi

    info "Habilitando 'user_allow_other' en $fuse_conf..."

    # Crear backup si el archivo existe
    if [[ -f "$fuse_conf" ]]; then
        sudo cp "$fuse_conf" "${fuse_conf}.backup"
    fi

    # Añadir user_allow_other
    echo "user_allow_other" | sudo tee -a "$fuse_conf" >/dev/null

    log "✅ FUSE configurado correctamente"
}

# Configurar montaje automático al arranque (Linux)
setup_auto_mount() {
    log "🔧 Configurando montaje automático al arranque..."

    # Verificar que estamos en Linux
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "Este script solo funciona en Linux"
        return 1
    fi

    # Configurar FUSE primero
    configure_fuse

    # Crear directorio de montaje si no existe
    local mount_dir="$HOME/OneDrive"
    mkdir -p "$mount_dir"

    setup_systemd_service "$mount_dir"
}

# Crear servicio systemd para Linux
setup_systemd_service() {
    local mount_dir="$1"
    local current_user=$(whoami)
    local user_home=$(eval echo "~$current_user")
    local service_file="/etc/systemd/system/onedrive-rclone@.service"

    log "📝 Creando servicio systemd de sistema..."

    # Crear servicio de sistema con plantilla de usuario
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=OneDrive (rclone) for %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=%i
Group=%i
ExecStartPre=/bin/mkdir -p /home/%i/OneDrive
ExecStart=/usr/bin/rclone mount onedrive: /home/%i/OneDrive \\
    --config=/home/%i/.config/rclone/rclone.conf \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-age 100h \\
    --vfs-cache-max-size 10G \\
    --vfs-cache-poll-interval 15s \\
    --dir-cache-time 5m \\
    --poll-interval 15s \\
    --umask 002 \\
    --allow-other
ExecStop=/bin/fusermount -u /home/%i/OneDrive
Restart=always
RestartSec=10
Environment=PATH=/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

    # Habilitar el servicio para el usuario actual
    sudo systemctl daemon-reload
    sudo systemctl enable "onedrive-rclone@${current_user}.service"

    log "✅ Servicio systemd creado y habilitado para $current_user"
    info "Para iniciar ahora: sudo systemctl start onedrive-rclone@${current_user}.service"
    info "Para ver logs: journalctl -u onedrive-rclone@${current_user}.service -f"
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
    info "  • Iniciar servicio: sudo systemctl start onedrive-rclone@$(whoami).service"
    info "  • Ver estado: sudo systemctl status onedrive-rclone@$(whoami).service"
    info "  • Ver logs: journalctl -u onedrive-rclone@$(whoami).service -f"
    info "  • Deshabilitar: sudo systemctl disable onedrive-rclone@$(whoami).service"
    echo
}

# Función para diagnosticar el servicio
diagnose_service() {
    log "🔍 Diagnosticando el servicio OneDrive..."
    echo

    local current_user=$(whoami)
    local service_name="onedrive-rclone@${current_user}.service"
    local service_file="/etc/systemd/system/onedrive-rclone@.service"

    # Verificar si el servicio existe
    if [[ ! -f "$service_file" ]]; then
        error "Servicio no encontrado en $service_file"
        return 1
    fi
    log "✅ Archivo de servicio existe"

    # Verificar estado del servicio
    echo
    info "📊 Estado del servicio:"
    if sudo systemctl is-enabled "$service_name" >/dev/null 2>&1; then
        log "✅ Servicio habilitado"
    else
        warn "❌ Servicio NO habilitado"
        info "Ejecuta: sudo systemctl enable $service_name"
    fi

    if sudo systemctl is-active "$service_name" >/dev/null 2>&1; then
        log "✅ Servicio activo"
    else
        warn "❌ Servicio NO activo"
        info "Ejecuta: sudo systemctl start $service_name"
    fi

    # Verificar si el directorio está montado
    echo
    info "📁 Estado del montaje:"
    local mount_dir="$HOME/OneDrive"
    if mountpoint -q "$mount_dir" 2>/dev/null; then
        log "✅ OneDrive está montado en $mount_dir"
        local file_count
        file_count=$(ls -1 "$mount_dir" 2>/dev/null | wc -l)
        info "Archivos disponibles: $file_count"
    else
        warn "❌ OneDrive NO está montado en $mount_dir"
    fi

    # Mostrar logs recientes
    echo
    info "📝 Logs del servicio (últimas 10 líneas):"
    sudo journalctl -u "$service_name" --no-pager -n 10

    # Verificar configuración rclone
    echo
    info "🔧 Configuración rclone:"
    if rclone listremotes 2>/dev/null | grep -q "onedrive:"; then
        log "✅ OneDrive configurado en rclone"
        if rclone about onedrive: >/dev/null 2>&1; then
            log "✅ Conexión a OneDrive OK"
        else
            warn "❌ No se puede conectar a OneDrive (token expirado?)"
        fi
    else
        error "❌ OneDrive no configurado en rclone"
        info "Ejecuta: rclone config"
    fi

    # Verificar dependencias
    echo
    info "🔍 Verificando dependencias:"
    if command -v fusermount >/dev/null 2>&1; then
        log "✅ fusermount disponible"
    else
        error "❌ fusermount no encontrado (instala: sudo apt install fuse)"
    fi

    # Verificar configuración FUSE
    local fuse_conf="/etc/fuse.conf"
    if [[ -f "$fuse_conf" ]] && grep -q "^user_allow_other" "$fuse_conf"; then
        log "✅ FUSE configurado (user_allow_other habilitado)"
    else
        warn "❌ FUSE no configurado - falta 'user_allow_other' en $fuse_conf"
        info "Ejecuta el script de nuevo para configurar automáticamente"
    fi

    # Sugerencias de reparación
    echo
    info "🛠️  Comandos para reparar:"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable $service_name"
    echo "  sudo systemctl start $service_name"
    echo "  sudo systemctl status $service_name"
}

# Función para reparar el servicio
repair_service() {
    log "🔧 Reparando servicio OneDrive..."

    local current_user=$(whoami)
    local service_name="onedrive-rclone@${current_user}.service"

    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"

    info "¿Iniciar el servicio ahora? (y/n)"
    read -r start_now

    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        sudo systemctl start "$service_name"
        sleep 2
        diagnose_service
    fi
}

# Función principal
main() {
    # Si se pasa argumento 'diagnose' o 'repair'
    if [[ "${1:-}" == "diagnose" ]]; then
        diagnose_service
        return
    elif [[ "${1:-}" == "repair" ]]; then
        repair_service
        return
    fi

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
