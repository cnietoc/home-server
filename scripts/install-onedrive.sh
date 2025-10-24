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
    log "🔧 Verificando configuración de OneDrive..."

    # Verificar si ya existe una configuración de OneDrive
    if rclone listremotes 2>/dev/null | grep -q "onedrive:"; then
        info "OneDrive ya está configurado:"
        rclone listremotes | grep "onedrive:"
        echo
        info "¿Quieres reconfigurar OneDrive? (y/n)"
        read -r reconfigure

        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            log "✅ Usando configuración existente de OneDrive"
            return 0
        fi

        log "Reconfigurando OneDrive..."
    else
        log "Configurando OneDrive por primera vez..."
    fi

    warn "⚠️  SERVIDOR SIN NAVEGADOR DETECTADO"
    echo
    info "Para configurar OneDrive en un servidor sin navegador tienes 2 opciones:"
    echo
    info "📋 OPCIÓN 1 - Configuración remota (RECOMENDADA):"
    info "1. Configura rclone en tu PC local con navegador"
    info "2. Copia el archivo de configuración al servidor"
    echo
    info "📋 OPCIÓN 2 - Configuración manual en el servidor:"
    info "1. Usaremos autenticación manual sin auto-config"
    echo
    info "¿Qué opción prefieres?"
    info "1) Configuración remota (necesitas acceso a un PC con navegador)"
    info "2) Configuración manual en el servidor"
    info "3) Salir y configurar más tarde"
    echo
    read -p "Opción (1/2/3): " option

    case $option in
        1)
            configure_onedrive_remote
            ;;
        2)
            configure_onedrive_manual
            ;;
        3|*)
            info "Puedes configurar OneDrive más tarde con: rclone config"
            return 1
            ;;
    esac

    log "✅ Configuración de OneDrive completada"
}

# Configuración remota (desde PC local)
configure_onedrive_remote() {
    log "🔧 Configuración remota de OneDrive..."
    echo
    info "PASO 1 - En tu PC LOCAL (con navegador):"
    info "1. Instala rclone: curl https://rclone.org/install.sh | sudo bash"
    info "2. Ejecuta: rclone config"
    info "3. Configura OneDrive normalmente (con auto-config)"
    info "4. Encuentra el archivo de configuración:"
    echo
    info "   Linux/macOS: ~/.config/rclone/rclone.conf"
    info "   Windows: %APPDATA%\\rclone\\rclone.conf"
    echo
    info "PASO 2 - Copia la configuración al servidor:"
    info "1. Copia el contenido del archivo rclone.conf"
    info "2. Pégalo en este servidor"
    echo
    warn "⚠️  Presiona ENTER cuando tengas lista la configuración de tu PC local..."
    read -r

    local config_dir="$HOME/.config/rclone"
    local config_file="$config_dir/rclone.conf"

    mkdir -p "$config_dir"

    info "Pega aquí el contenido completo de tu archivo rclone.conf:"
    info "(Termina con una línea vacía y luego Ctrl+D)"
    echo

    cat > "$config_file"

    if [[ -s "$config_file" ]]; then
        log "✅ Configuración copiada correctamente"

        # Verificar que funciona
        if rclone listremotes | grep -q "onedrive:"; then
            log "✅ OneDrive configurado y detectado"
        else
            warn "⚠️  No se detectó configuración de OneDrive. Verifica el contenido."
        fi
    else
        error "❌ No se recibió configuración. Usa: rclone config para configurar manualmente"
        return 1
    fi
}

# Configuración manual (sin navegador)
configure_onedrive_manual() {
    log "🔧 Configuración manual de OneDrive..."
    echo
    warn "⚠️  IMPORTANTE: Esta opción requiere pasos manuales adicionales"
    echo
    info "Sigue estos pasos en el configurador:"
    echo
    info "1. Elige 'n' para nueva configuración remota"
    info "2. Nombre: 'onedrive'"
    info "3. Tipo: Busca 'Microsoft OneDrive' y selecciona el número"
    info "4. client_id: Presiona Enter (predeterminado)"
    info "5. client_secret: Presiona Enter (predeterminado)"
    info "6. region: Elige '1' para Microsoft Cloud Global"
    info "7. Editar configuración avanzada: 'n' (no)"
    info "8. Auto config: 'n' (NO - importante para servidores)"
    info "9. Se mostrará una URL - CÓPIALA y ábrela en tu navegador"
    info "10. Autoriza la aplicación y copia el código de respuesta"
    info "11. Pega el código en el terminal"
    info "12. Tipo de configuración: '1' para OneDrive Personal"
    info "13. Confirma con 'y' para guardar"
    echo
    warn "⚠️  Presiona ENTER cuando estés listo para continuar..."
    read -r

    rclone config
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
