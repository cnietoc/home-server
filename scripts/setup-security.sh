#!/usr/bin/env bash
set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función de logging con colores
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $*"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $*"
}

info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️${NC} $*"
}



# Configurar fail2ban para protección SSH
configure_fail2ban() {
    log "🛡️ Configurando Fail2Ban para protección SSH..."

    # Instalar fail2ban si no está instalado
    if ! command -v fail2ban-server >/dev/null 2>&1; then
        log "Instalando Fail2Ban..."
        sudo apt-get update
        sudo apt-get install -y fail2ban
    else
        info "Fail2Ban ya está instalado"
    fi

    # Configurar jail local (siempre actualizar para garantizar configuración correcta)
    local jail_local="/etc/fail2ban/jail.local"
    local jail_backup="/etc/fail2ban/jail.local.backup.$(date +%Y%m%d_%H%M%S)"

    # Hacer backup si existe configuración anterior
    if [[ -f "$jail_local" ]]; then
        sudo cp "$jail_local" "$jail_backup"
        log "Backup creado: $jail_backup"
    fi

    log "Configurando Fail2Ban..."
    cat << EOF | sudo tee "$jail_local" >/dev/null
[DEFAULT]
# Tiempo de baneo en segundos (30 minutos)
bantime = 1800

# Tiempo de ventana para contar intentos fallidos (10 minutos)
findtime = 600

# Máximo número de intentos fallidos antes del baneo
maxretry = 5

# Ignorar IPs locales
ignoreip = 127.0.0.1/8 ::1 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
    log "✅ Configuración de Fail2Ban actualizada"

    # Validar configuración antes de aplicar
    if sudo fail2ban-client -t >/dev/null 2>&1; then
        log "Configuración de Fail2Ban validada"

        # Reiniciar y habilitar fail2ban
        sudo systemctl restart fail2ban
        sudo systemctl enable fail2ban

        # Verificar que el servicio se inició correctamente
        sleep 2
        if sudo systemctl is-active --quiet fail2ban; then
            log "✅ Fail2Ban configurado y activado correctamente"
        else
            error "❌ Error: Fail2Ban no pudo iniciarse correctamente"
            sudo systemctl status fail2ban
            return 1
        fi
    else
        error "❌ Error en configuración de Fail2Ban, restaurando backup..."
        if [[ -f "$jail_backup" ]]; then
            sudo cp "$jail_backup" "$jail_local"
        fi
        return 1
    fi

    # Mostrar estado
    echo ""
    log "📋 Estado de Fail2Ban:"
    sudo fail2ban-client status
}

# Configurar actualizaciones automáticas de seguridad
configure_auto_updates() {
    log "🔄 Configurando actualizaciones automáticas de seguridad..."

    # Instalar unattended-upgrades si no está instalado
    if ! dpkg -l | grep -q unattended-upgrades; then
        log "Instalando unattended-upgrades..."
        sudo apt-get update
        sudo apt-get install -y unattended-upgrades
    else
        info "unattended-upgrades ya está instalado"
    fi

    # Configurar actualizaciones automáticas (siempre actualizar)
    local auto_upgrades="/etc/apt/apt.conf.d/20auto-upgrades"
    local auto_upgrades_backup="/etc/apt/apt.conf.d/20auto-upgrades.backup.$(date +%Y%m%d_%H%M%S)"

    # Hacer backup si existe configuración anterior
    if [[ -f "$auto_upgrades" ]]; then
        sudo cp "$auto_upgrades" "$auto_upgrades_backup"
        log "Backup de actualizaciones automáticas: $auto_upgrades_backup"
    fi

    log "Configurando actualizaciones automáticas..."
    cat << EOF | sudo tee "$auto_upgrades" >/dev/null
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    log "✅ Configuración de actualizaciones automáticas actualizada"

    # Configurar unattended-upgrades (siempre actualizar completamente)
    local unattended_config="/etc/apt/apt.conf.d/50unattended-upgrades"
    local unattended_backup="/etc/apt/apt.conf.d/50unattended-upgrades.backup.$(date +%Y%m%d_%H%M%S)"

    if [[ -f "$unattended_config" ]]; then
        # Hacer backup de la configuración original
        sudo cp "$unattended_config" "$unattended_backup"
        log "Backup de unattended-upgrades: $unattended_backup"

        # Crear configuración personalizada completa
        log "Aplicando configuración personalizada de unattended-upgrades..."

        # Obtener información del sistema para la configuración
        . /etc/os-release
        local distro_id="$ID"
        local distro_codename="$VERSION_CODENAME"

        cat << EOF | sudo tee "$unattended_config" >/dev/null
// Automatically upgrade packages from these (origin:archive) pairs
Unattended-Upgrade::Allowed-Origins {
        "\${distro_id}:\${distro_codename}";
        "\${distro_id}:\${distro_codename}-security";
        "\${distro_id}ESMApps:\${distro_codename}-apps-security";
        "\${distro_id}ESM:\${distro_codename}-infra-security";
};

// Python regular expressions, matching packages to exclude from upgrading
Unattended-Upgrade::Package-Blacklist {
};

// This option allows you to control if on a unclean dpkg exit
// unattended-upgrades will automatically run
//   dpkg --force-confold --configure -a
// The default is true, to ensure updates keep getting installed
Unattended-Upgrade::AutoFixInterruptedDpkg "true";

// Split the upgrade into the smallest possible chunks so that
// they can be interrupted with SIGUSR1. This makes the upgrade
// a bit slower but it has the benefit that shutdown while a upgrade
// is running is possible (with a small delay)
Unattended-Upgrade::MinimalSteps "true";

// Install all updates when the machine is shutting down
// instead of doing it in the background while the machine is running.
// This will (obviously) make shutdown slower.
Unattended-Upgrade::InstallOnShutdown "false";

// Send email to this address for problems or packages upgrades
// If empty or unset then no email is sent, make sure that you
// have a working mail setup on your system. A package that provides
// 'mailx' must be installed. E.g. "user@example.com"
//Unattended-Upgrade::Mail "";

// Set this value to one of:
//    "always", "only-on-error" or "on-change"
// If this is not set, then any legacy MailOnlyOnError (boolean) value
// is used to chose between "only-on-error" and "on-change"
//Unattended-Upgrade::MailReport "on-change";

// Remove unused automatically installed kernel-related packages
// (kernel images, kernel headers and kernel version locked tools).
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Do automatic removal of newly unused dependencies after the upgrade
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";

// Do automatic removal of unused packages after the upgrade
// (equivalent to apt autoremove)
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot *WITHOUT CONFIRMATION* if
//  the file /var/run/reboot-required is found after the upgrade
Unattended-Upgrade::Automatic-Reboot "true";

// Automatically reboot even if there are users currently logged in
// when Unattended-Upgrade::Automatic-Reboot is set to true
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";

// If automatic reboot is enabled and needed, reboot at the specific
// time instead of immediately
//  Default: "now"
Unattended-Upgrade::Automatic-Reboot-Time "03:00";

// Use apt bandwidth limit feature, this example limits the download
// speed to 70kb/sec
//Acquire::http::Dl-Limit "70";

// Enable logging to syslog. Default is False
Unattended-Upgrade::SyslogEnable "true";

// Specify syslog facility. Default is daemon
Unattended-Upgrade::SyslogFacility "daemon";

// Download and install upgrades only on AC power
// (i.e. skip or gracefully stop updates on battery)
// Unattended-Upgrade::OnlyOnACPower "true";

// Download and install upgrades only on non-metered connection
// (i.e. skip or gracefully stop updates on a metered connection)
// Unattended-Upgrade::Skip-Updates-On-Metered-Connections "true";

// Verbose logging
// Unattended-Upgrade::Verbose "false";

// Print debugging information both in unattended-upgrades and
// in unattended-upgrade-shutdown
// Unattended-Upgrade::Debug "false";
EOF
        log "✅ Configuración personalizada de unattended-upgrades aplicada"
    else
        warn "Archivo unattended-upgrades no encontrado, se creará en la próxima instalación"
    fi

    # Habilitar y reiniciar el servicio para aplicar cambios
    sudo systemctl enable unattended-upgrades

    # Reiniciar el servicio si ya estaba corriendo, o iniciarlo si no
    if sudo systemctl is-active --quiet unattended-upgrades; then
        log "Reiniciando servicio unattended-upgrades para aplicar cambios..."
        sudo systemctl restart unattended-upgrades
    else
        log "Iniciando servicio unattended-upgrades..."
        sudo systemctl start unattended-upgrades
    fi

    # Verificar que el servicio está corriendo correctamente
    sleep 2
    if sudo systemctl is-active --quiet unattended-upgrades; then
        log "✅ Actualizaciones automáticas de seguridad activadas correctamente"

        # Verificar configuración ejecutando una prueba en seco
        if sudo unattended-upgrade --dry-run >/dev/null 2>&1; then
            log "✅ Configuración de actualizaciones automáticas validada"
        else
            warn "⚠️ Posible problema en configuración, revisar logs: sudo journalctl -u unattended-upgrades"
        fi
    else
        error "❌ Error: Servicio unattended-upgrades no pudo iniciarse"
        sudo systemctl status unattended-upgrades
        return 1
    fi
}

# Función para mostrar información de seguridad
show_security_status() {
    log "📊 Estado de seguridad del servidor:"
    echo ""

    # Fail2Ban
    log "🛡️ Fail2Ban:"
    if command -v fail2ban-client >/dev/null 2>&1; then
        sudo fail2ban-client status
    else
        warn "Fail2Ban no está instalado"
    fi
    echo ""

    # Actualizaciones
    log "🔄 Actualizaciones automáticas:"
    if systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
        info "✅ Actualizaciones automáticas habilitadas"
    else
        warn "❌ Actualizaciones automáticas no habilitadas"
    fi
}

# Función de ayuda
show_help() {
    cat << EOF
Uso: $0 [opciones]

DESCRIPCIÓN:
  Configura la seguridad básica del servidor Ubuntu (fail2ban, actualizaciones automáticas)
  Optimizado para servidores caseros detrás de router (sin firewall UFW)
  Para configuración SSH usar: ./scripts/setup-ssh.sh

OPCIONES:
  --fail2ban-only     Solo configurar Fail2Ban
  --auto-updates-only Solo configurar actualizaciones automáticas
  --status            Mostrar estado actual de seguridad
  --help              Mostrar esta ayuda

EJEMPLOS:
  $0                    # Configuración completa de seguridad
  $0 --fail2ban-only    # Solo configurar Fail2Ban
  $0 --status           # Ver estado de seguridad actual

NOTA:
  - Este script no modifica la configuración SSH
  - Para configurar SSH usar: ./scripts/setup-ssh.sh

EOF
}

# Función principal
main() {
    local fail2ban_only=false
    local auto_updates_only=false
    local status_only=false

    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --fail2ban-only)
                fail2ban_only=true
                shift
                ;;
            --auto-updates-only)
                auto_updates_only=true
                shift
                ;;
            --status)
                status_only=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Verificar permisos sudo
    if ! sudo -v >/dev/null 2>&1; then
        error "Este script requiere permisos de sudo"
        exit 1
    fi

    if [[ "$status_only" == "true" ]]; then
        show_security_status
        return 0
    fi

    log "🛡️ Configurando seguridad del servidor Ubuntu..."
    echo ""

    if [[ "$fail2ban_only" == "true" ]]; then
        configure_fail2ban
    elif [[ "$auto_updates_only" == "true" ]]; then
        configure_auto_updates
    else
        # Configuración completa
        configure_fail2ban
        configure_auto_updates
    fi

    echo ""
    log "✅ Configuración de seguridad completada"

    # Mostrar estado final
    show_security_status
}

# Manejar señales de interrupción
trap 'error "Configuración interrumpida"; exit 130' INT TERM

# Ejecutar función principal
main "$@"
