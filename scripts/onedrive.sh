#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ONEDRIVE SYNC MANAGER - Script para setup y gestión de sincronización con OneDrive usando rclone y systemd
# ============================================================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RCLONE_CONFIG_DIR="${HOME}/.config/rclone"
RCLONE_CONFIG_FILE="${RCLONE_CONFIG_DIR}/rclone.conf"
REMOTE_NAME="onedrive"
SELECTED_FOLDER=""
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
BACKUP_SERVICE="home-server-backup-sync"
CONFIG_SERVICE="home-server-config-sync"

# Logging
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $*"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️${NC} $*"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $*"; }
header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $* ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
}
prompt() { echo -e "${MAGENTA}➜${NC} $*"; }

# Verificar si el sistema es compatible (Ubuntu/Debian/Linux)
check_system() {
    if [[ ! -f /etc/os-release ]]; then
        error "No se puede determinar el sistema operativo"
        exit 1
    fi

    . /etc/os-release
    log "✅ Sistema detectado: $PRETTY_NAME"
}

# Verificar e instalar rclone si no está instalado
install_rclone() {
    if command -v rclone >/dev/null 2>&1; then
        local version=$(rclone version 2>&1 | head -n1)
        info "rclone ya está instalado: $version"
        return 0
    fi

    header "Instalando rclone"

    log "Descargando e instalando rclone..."
    curl https://rclone.org/install.sh | sudo bash

    if command -v rclone >/dev/null 2>&1; then
        success "rclone instalado correctamente"
    else
        error "No se pudo instalar rclone"
        exit 1
    fi
}

# Verificar si ya existe una configuración de OneDrive
check_existing_remote() {
    if [[ -f "$RCLONE_CONFIG_FILE" ]] && rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
        return 0
    else
        return 1
    fi
}

# Configurar remoto de OneDrive
configure_onedrive_remote() {
    header "Configuración de OneDrive con rclone"

    # Crear directorio de configuración si no existe
    mkdir -p "$RCLONE_CONFIG_DIR"

    if check_existing_remote; then
        warn "Ya existe un remoto llamado '$REMOTE_NAME'"
        prompt "¿Deseas reconfigurarlo? (s/N): "
        read -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then
            info "Usando configuración existente"
            return 0
        fi

        log "Eliminando configuración existente..."
        rclone config delete "$REMOTE_NAME" 2>/dev/null || true
    fi

    echo ""
    log "🔧 Iniciando configuración interactiva de OneDrive..."
    echo ""
    info "INSTRUCCIONES:"
    echo -e "  1. Selecciona 'n' para crear un nuevo remoto"
    echo -e "  2. Nombre del remoto: ${GREEN}${REMOTE_NAME}${NC}"
    echo -e "  3. Tipo de almacenamiento: busca '${GREEN}onedrive${NC}' o su número"
    echo -e "  4. Client ID y Secret: déjalos ${GREEN}vacíos${NC} (presiona Enter)"
    echo -e "  5. Región: selecciona '${GREEN}1${NC}' (Microsoft Cloud Global)"
    echo -e "  6. Configuración avanzada: ${GREEN}No${NC}"
    echo -e "  7. Autorización automática: ${GREEN}Sí${NC}"
    echo -e "  8. Se abrirá un navegador para autorizar el acceso"
    echo -e "  9. Tipo de configuración: ${GREEN}1${NC} (OneDrive Personal o Business)"
    echo -e "  10. Confirma la selección y guarda"
    echo ""
    warn "⚠️  Asegúrate de tener un navegador disponible para la autorización"
    echo ""
    prompt "Presiona Enter para continuar..."
    read -r

    # Ejecutar configuración interactiva
    rclone config

    # Verificar que se creó el remoto
    if check_existing_remote; then
        success "Remoto '$REMOTE_NAME' configurado correctamente"
        return 0
    else
        error "No se pudo configurar el remoto '$REMOTE_NAME'"
        exit 1
    fi
}

# Listar carpetas de OneDrive de forma interactiva
list_onedrive_folders() {
    local current_path="$1"
    local display_path="${current_path:-/}"

    echo ""
    header "Navegando en OneDrive: $display_path"

    log "Obteniendo lista de carpetas..."

    # Obtener carpetas
    local folders=()
    while IFS= read -r line; do
        folders+=("$line")
    done < <(rclone lsd "${REMOTE_NAME}:${current_path}" 2>/dev/null | awk '{$1=$2=$3=$4=""; print substr($0,5)}' | sed 's/^[[:space:]]*//')

    if [[ ${#folders[@]} -eq 0 ]]; then
        warn "No se encontraron subcarpetas en esta ubicación"
    else
        echo ""
        info "Carpetas disponibles:"
        for i in "${!folders[@]}"; do
            echo -e "  ${CYAN}$((i+1)).${NC} ${folders[$i]}"
        done
    fi

    echo ""
    echo -e "Opciones:"
    echo -e "  ${GREEN}[número]${NC} - Entrar en una carpeta"
    echo -e "  ${GREEN}..${NC}       - Volver atrás"
    echo -e "  ${GREEN}.${NC}        - Usar la carpeta actual"
    echo -e "  ${GREEN}q${NC}        - Cancelar y salir"
    echo ""
    prompt "Selección: "
    read -r selection

    case "$selection" in
        q|Q)
            error "Configuración cancelada por el usuario"
            exit 0
            ;;
        .)
            SELECTED_FOLDER="$current_path"
            return 0
            ;;
        ..)
            if [[ -n "$current_path" ]]; then
                local parent_path=$(dirname "$current_path")
                [[ "$parent_path" == "." ]] && parent_path=""
                list_onedrive_folders "$parent_path"
            else
                warn "Ya estás en la raíz"
                list_onedrive_folders "$current_path"
            fi
            ;;
        *)
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#folders[@]} ]]; then
                local selected_folder="${folders[$((selection-1))]}"
                local new_path="${current_path:+$current_path/}${selected_folder}"
                list_onedrive_folders "$new_path"
            else
                error "Selección inválida"
                list_onedrive_folders "$current_path"
            fi
            ;;
    esac
}

# Navegación interactiva para seleccionar carpeta
select_onedrive_folder() {
    header "Selección de carpeta de trabajo en OneDrive"

    echo ""
    info "Vamos a seleccionar la carpeta donde se sincronizarán los backups"
    echo ""

    # Verificar conectividad
    log "Verificando conexión con OneDrive..."
    if ! rclone lsd "${REMOTE_NAME}:" >/dev/null 2>&1; then
        error "No se pudo conectar con OneDrive. Verifica tu configuración."
        exit 1
    fi
    success "Conexión con OneDrive verificada"

    # Iniciar navegación
    list_onedrive_folders ""

    echo ""
    success "Carpeta seleccionada: ${CYAN}${SELECTED_FOLDER:-/}${NC}"

    # Crear la estructura de carpetas en OneDrive si no existe
    log "Verificando estructura de carpetas en OneDrive..."

    local base_path="${SELECTED_FOLDER:+$SELECTED_FOLDER/}"
    rclone mkdir "${REMOTE_NAME}:${base_path}/backups" 2>/dev/null || true
    rclone mkdir "${REMOTE_NAME}:${base_path}/config" 2>/dev/null || true

    success "Estructura de carpetas creada en OneDrive"

    # Guardar la ruta seleccionada
    echo "$base_path" > "${PROJECT_ROOT}/.onedrive-path"
}

# Crear servicio systemd para sincronización de backups
create_backup_sync_service() {
    local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")

    header "Creando servicio de sincronización de backups"

    mkdir -p "$SYSTEMD_USER_DIR"

    # Crear archivo de servicio
    cat > "${SYSTEMD_USER_DIR}/home-server-backup-sync.service" <<EOF
[Unit]
Description=Home Server - Sincronización de Backups a OneDrive
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
# Prevenir ejecuciones simultáneas
ExecStartPre=/bin/bash -c 'if [ -f ${PROJECT_ROOT}/logs/backup-sync.lock ]; then echo "Sincronización ya en curso"; exit 1; fi'
ExecStartPre=/bin/bash -c 'echo $$ > ${PROJECT_ROOT}/logs/backup-sync.lock'
ExecStart=/usr/bin/rclone sync \\
    ${PROJECT_ROOT}/backups \\
    ${REMOTE_NAME}:${onedrive_path}/backups \\
    --delete-during \\
    --verbose \\
    --log-file=${PROJECT_ROOT}/logs/rclone-backup-sync.log \\
    --log-level INFO \\
    --exclude .gitignore \\
    --transfers 8 \\
    --checkers 16 \\
    --buffer-size 32M \\
    --use-mmap \\
    --fast-list \\
    --contimeout 60s \\
    --timeout 0 \\
    --retries 5 \\
    --low-level-retries 20 \\
    --stats 1m \\
    --stats-one-line
ExecStopPost=/bin/bash -c 'rm -f ${PROJECT_ROOT}/logs/backup-sync.lock'

[Install]
WantedBy=default.target
EOF

    # Crear archivo timer
    cat > "${SYSTEMD_USER_DIR}/home-server-backup-sync.timer" <<EOF
[Unit]
Description=Timer para sincronización de backups diaria a las 3 AM
Requires=home-server-backup-sync.service

[Timer]
OnCalendar=*-*-* 03:00:00
OnBootSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    success "Servicio de sincronización de backups creado"
}

# Crear servicio systemd para sincronización de config
create_config_sync_service() {
    local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")

    header "Creando servicio de sincronización de configuración"

    mkdir -p "$SYSTEMD_USER_DIR"

    # Crear archivo de servicio
    cat > "${SYSTEMD_USER_DIR}/home-server-config-sync.service" <<EOF
[Unit]
Description=Home Server - Sincronización de config.toml a OneDrive
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
# Prevenir ejecuciones simultáneas
ExecStartPre=/bin/bash -c 'if [ -f ${PROJECT_ROOT}/logs/config-sync.lock ]; then echo "Sincronización ya en curso"; exit 1; fi'
ExecStartPre=/bin/bash -c 'echo $$ > ${PROJECT_ROOT}/logs/config-sync.lock'
ExecStart=/usr/bin/rclone copyto \\
    ${PROJECT_ROOT}/config.toml \\
    ${REMOTE_NAME}:${onedrive_path}/config/config.toml \\
    --verbose \\
    --log-file=${PROJECT_ROOT}/logs/rclone-config-sync.log \\
    --log-level INFO \\
    --contimeout 60s \\
    --timeout 300s \\
    --retries 3
ExecStopPost=/bin/bash -c 'rm -f ${PROJECT_ROOT}/logs/config-sync.lock'

[Install]
WantedBy=default.target
EOF

    # Crear archivo timer
    cat > "${SYSTEMD_USER_DIR}/home-server-config-sync.timer" <<EOF
[Unit]
Description=Timer para sincronización de config.toml cada hora
Requires=home-server-config-sync.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    success "Servicio de sincronización de configuración creado"
}

# Habilitar e iniciar servicios systemd
enable_systemd_services() {
    header "Habilitando servicios systemd"

    # Recargar systemd
    log "Recargando configuración de systemd..."
    systemctl --user daemon-reload

    # Habilitar e iniciar timers
    log "Habilitando timer de sincronización de backups..."
    systemctl --user enable home-server-backup-sync.timer
    systemctl --user start home-server-backup-sync.timer

    log "Habilitando timer de sincronización de configuración..."
    systemctl --user enable home-server-config-sync.timer
    systemctl --user start home-server-config-sync.timer

    # Habilitar lingering para que los servicios se ejecuten aunque no haya sesión
    if loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=no"; then
        log "Habilitando lingering para usuario $(whoami)..."
        sudo loginctl enable-linger "$(whoami)"
    fi

    success "Servicios systemd habilitados y en ejecución"
}

# Ejecutar sincronización inicial
run_initial_sync() {
    header "Ejecutando sincronización inicial"

    warn "Esto puede tardar varios minutos dependiendo del tamaño de tus backups..."
    echo ""

    # Sincronizar backups
    log "Sincronizando backups..."
    systemctl --user start home-server-backup-sync.service

    # Esperar a que termine
    while systemctl --user is-active --quiet home-server-backup-sync.service; do
        sleep 2
    done

    if systemctl --user is-failed --quiet home-server-backup-sync.service; then
        warn "La sincronización de backups tuvo problemas. Revisa los logs."
    else
        success "Backups sincronizados"
    fi

    # Sincronizar config
    log "Sincronizando config.toml..."
    systemctl --user start home-server-config-sync.service

    # Esperar a que termine
    while systemctl --user is-active --quiet home-server-config-sync.service; do
        sleep 1
    done

    if systemctl --user is-failed --quiet home-server-config-sync.service; then
        warn "La sincronización de configuración tuvo problemas. Revisa los logs."
    else
        success "Configuración sincronizada"
    fi
}

# Mostrar información final
show_final_info() {
    local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")

    echo ""
    header "🎉 Configuración completada exitosamente"
    echo ""

    success "Resumen de la configuración:"
    echo ""
    echo -e "  ${CYAN}Remoto rclone:${NC}        ${REMOTE_NAME}"
    echo -e "  ${CYAN}Carpeta OneDrive:${NC}     ${onedrive_path}"
    echo -e "  ${CYAN}Carpeta local backups:${NC} ${PROJECT_ROOT}/backups"
    echo -e "  ${CYAN}Archivo config.toml:${NC}  ${PROJECT_ROOT}/config.toml"
    echo ""

    info "Servicios configurados:"
    echo -e "  ${GREEN}✓${NC} home-server-backup-sync  - Sincroniza backups diariamente a las 3 AM"
    echo -e "  ${GREEN}✓${NC} home-server-config-sync  - Sincroniza config.toml cada hora"
    echo ""

    info "Comportamiento especial:"
    echo -e "  ${GREEN}✓${NC} Si el PC está apagado a las 3 AM, el backup se ejecuta al arrancar"
    echo -e "  ${GREEN}✓${NC} Los archivos borrados localmente se borran también en OneDrive"
    echo -e "  ${GREEN}✓${NC} OneDrive mantiene papelera de reciclaje (30 días de recuperación)"
    echo ""

    info "Comandos útiles:"
    echo ""
    echo -e "  ${CYAN}# Ver estado de los servicios${NC}"
    echo "  systemctl --user status home-server-backup-sync.timer"
    echo "  systemctl --user status home-server-config-sync.timer"
    echo ""
    echo -e "  ${CYAN}# Ver logs de sincronización${NC}"
    echo "  journalctl --user -u home-server-backup-sync.service -f"
    echo "  journalctl --user -u home-server-config-sync.service -f"
    echo ""
    echo -e "  ${CYAN}# Forzar sincronización inmediata${NC}"
    echo "  systemctl --user start home-server-backup-sync.service"
    echo "  systemctl --user start home-server-config-sync.service"
    echo ""
    echo -e "  ${CYAN}# Ver archivos en rclone${NC}"
    echo "  cat ${PROJECT_ROOT}/logs/rclone-backup-sync.log"
    echo "  cat ${PROJECT_ROOT}/logs/rclone-config-sync.log"
    echo ""
    echo -e "  ${CYAN}# Deshabilitar sincronización${NC}"
    echo "  systemctl --user stop home-server-backup-sync.timer"
    echo "  systemctl --user disable home-server-backup-sync.timer"
    echo ""

    success "¡Todo listo! Tus backups y configuración se sincronizarán automáticamente con OneDrive."
}

# ============================================================================
# FUNCIONES DE GESTIÓN
# ============================================================================

# Mostrar estado
show_status() {
    header "Estado de Sincronización OneDrive"
    echo ""

    local backup_timer_status=$(systemctl --user is-active ${BACKUP_SERVICE}.timer 2>/dev/null || echo "inactive")
    local config_timer_status=$(systemctl --user is-active ${CONFIG_SERVICE}.timer 2>/dev/null || echo "inactive")

    echo -e "${BLUE}Servicios:${NC}"
    if [[ "$backup_timer_status" == "active" ]]; then
        echo -e "  ${GREEN}●${NC} Backup sync: ${GREEN}activo${NC}"
    else
        echo -e "  ${RED}●${NC} Backup sync: ${RED}inactivo${NC}"
    fi

    if [[ "$config_timer_status" == "active" ]]; then
        echo -e "  ${GREEN}●${NC} Config sync: ${GREEN}activo${NC}"
    else
        echo -e "  ${RED}●${NC} Config sync: ${RED}inactivo${NC}"
    fi

    echo ""
    echo -e "${BLUE}Próximas ejecuciones:${NC}"
    systemctl --user list-timers ${BACKUP_SERVICE}.timer ${CONFIG_SERVICE}.timer 2>/dev/null | grep -E "NEXT|home-server" || echo "  No programado"

    if [[ -f "${PROJECT_ROOT}/.onedrive-path" ]]; then
        local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")
        echo ""
        echo -e "${BLUE}Configuración:${NC}"
        echo "  Ruta OneDrive: onedrive:${onedrive_path}"
        echo "  Carpeta local: ${PROJECT_ROOT}/backups"
    fi
}

# Sincronizar ahora
sync_now() {
    local service=$1
    local name=$2

    log "Sincronizando ${name}..."
    systemctl --user start ${service}.service

    local timeout=300
    local elapsed=0

    while systemctl --user is-active --quiet ${service}.service; do
        sleep 2
        elapsed=$((elapsed + 2))
        [[ $elapsed -ge $timeout ]] && { warn "Timeout"; return 1; }
        [[ $((elapsed % 10)) -eq 0 ]] && echo -n "."
    done

    echo ""

    if systemctl --user is-failed --quiet ${service}.service; then
        error "Sincronización de ${name} falló"
        journalctl --user -u ${service}.service -n 20 --no-pager
        return 1
    else
        success "Sincronización de ${name} completada"
        return 0
    fi
}

# Ver logs
show_logs() {
    local service=$1
    local lines=${2:-50}

    header "Logs de ${service}"
    journalctl --user -u ${service}.service -n ${lines} --no-pager
}

# Logs en vivo
follow_logs() {
    local service=$1
    header "Logs en vivo de ${service} (Ctrl+C para salir)"
    journalctl --user -u ${service}.service -f
}

# Habilitar/deshabilitar servicios
toggle_services() {
    local action=$1

    log "${action^} servicios..."
    systemctl --user ${action} ${BACKUP_SERVICE}.timer
    systemctl --user ${action} ${CONFIG_SERVICE}.timer

    if [[ "$action" == "enable" ]]; then
        systemctl --user start ${BACKUP_SERVICE}.timer
        systemctl --user start ${CONFIG_SERVICE}.timer
    fi

    success "Servicios ${action}dos"
}

# Verificar salud
check_health() {
    header "Verificación de salud"
    echo ""

    local errors=0

    command -v rclone >/dev/null 2>&1 && success "rclone instalado" || { error "rclone no instalado"; ((errors++)); }
    rclone listremotes 2>/dev/null | grep -q "^onedrive:" && success "OneDrive configurado" || { error "OneDrive no configurado"; ((errors++)); }
    rclone about onedrive: >/dev/null 2>&1 && success "Conectividad OK" || { error "Sin conexión a OneDrive"; ((errors++)); }
    systemctl --user list-unit-files | grep -q ${BACKUP_SERVICE} && success "Servicios instalados" || { error "Servicios no encontrados"; ((errors++)); }
    [[ -d "${PROJECT_ROOT}/backups" ]] && success "Carpeta backups OK" || warn "Carpeta backups no encontrada"
    [[ -f "${PROJECT_ROOT}/config.toml" ]] && success "config.toml OK" || warn "config.toml no encontrado"

    echo ""
    [[ $errors -eq 0 ]] && success "✅ Sistema OK" || error "❌ ${errors} errores"
    return $errors
}

# Listar archivos en OneDrive
list_onedrive() {
    [[ ! -f "${PROJECT_ROOT}/.onedrive-path" ]] && { error "OneDrive no configurado"; exit 1; }

    local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")
    header "Contenido en OneDrive: ${onedrive_path}"

    log "Backups:"
    rclone ls onedrive:${onedrive_path}/backups --max-depth 1 2>/dev/null || echo "  (vacío)"

    echo ""
    log "Config:"
    rclone ls onedrive:${onedrive_path}/config 2>/dev/null || echo "  (vacío)"
}

# Quitar sincronización completamente
remove_sync() {
    header "Desinstalando sincronización OneDrive"
    echo ""

    warn "Esto eliminará:"
    echo -e "  ${RED}●${NC} Servicios systemd (timers y services)"
    echo -e "  ${RED}●${NC} Archivo de configuración de ruta OneDrive (.onedrive-path)"
    echo -e "  ${RED}●${NC} Archivos de bloqueo"
    echo ""
    echo -e "  Los archivos en OneDrive y rclone.conf ${CYAN}se mantienen${NC}"
    echo ""

    prompt "¿Deseas continuar? (s/N): "
    read -r response
    if [[ ! "$response" =~ ^[Ss]$ ]]; then
        info "Operación cancelada"
        return 0
    fi

    log "Deteniendo servicios..."
    systemctl --user stop ${BACKUP_SERVICE}.timer 2>/dev/null || true
    systemctl --user stop ${CONFIG_SERVICE}.timer 2>/dev/null || true
    systemctl --user stop ${BACKUP_SERVICE}.service 2>/dev/null || true
    systemctl --user stop ${CONFIG_SERVICE}.service 2>/dev/null || true

    log "Deshabilitando servicios..."
    systemctl --user disable ${BACKUP_SERVICE}.timer 2>/dev/null || true
    systemctl --user disable ${CONFIG_SERVICE}.timer 2>/dev/null || true
    systemctl --user disable ${BACKUP_SERVICE}.service 2>/dev/null || true
    systemctl --user disable ${CONFIG_SERVICE}.service 2>/dev/null || true

    log "Eliminando archivos de servicio..."
    rm -f "${SYSTEMD_USER_DIR}/${BACKUP_SERVICE}.service" 2>/dev/null || true
    rm -f "${SYSTEMD_USER_DIR}/${BACKUP_SERVICE}.timer" 2>/dev/null || true
    rm -f "${SYSTEMD_USER_DIR}/${CONFIG_SERVICE}.service" 2>/dev/null || true
    rm -f "${SYSTEMD_USER_DIR}/${CONFIG_SERVICE}.timer" 2>/dev/null || true

    log "Recargando systemd..."
    systemctl --user daemon-reload

    log "Eliminando archivo de configuración..."
    rm -f "${PROJECT_ROOT}/.onedrive-path" 2>/dev/null || true

    log "Eliminando archivos de bloqueo..."
    rm -f "${PROJECT_ROOT}/logs/backup-sync.lock" 2>/dev/null || true
    rm -f "${PROJECT_ROOT}/logs/config-sync.lock" 2>/dev/null || true

    echo ""
    success "✅ Sincronización desinstalada completamente"
    echo ""
    info "Para reinstalar la sincronización, ejecuta:"
    echo -e "  ${CYAN}$0 setup${NC}"
    echo ""
    info "Para reconfigurar desde cero:"
    echo -e "  ${CYAN}$0 setup --force${NC}"
}

# Función de ayuda
show_help() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "  OneDrive Sync Manager - Setup y Gestión todo-en-uno"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}SETUP (Primera vez):${NC}"
    echo -e "  $0 setup              Configuración completa interactiva"
    echo -e "  $0 setup --force      Reconfigurar desde cero"
    echo ""
    echo -e "${GREEN}GESTIÓN:${NC}"
    echo -e "  $0 status             Estado de sincronización"
    echo -e "  $0 sync               Sincronizar todo ahora"
    echo -e "  $0 sync-backup        Sincronizar solo backups"
    echo -e "  $0 sync-config        Sincronizar solo config.toml"
    echo ""
    echo -e "  $0 logs [N]           Ver últimos N logs de backup"
    echo -e "  $0 logs-config [N]    Ver últimos N logs de config"
    echo -e "  $0 follow             Seguir logs de backup en vivo"
    echo -e "  $0 follow-config      Seguir logs de config en vivo"
    echo ""
    echo -e "  $0 enable             Habilitar sincronización automática"
    echo -e "  $0 disable            Deshabilitar sincronización automática"
    echo -e "  $0 restart            Reiniciar servicios"
    echo ""
    echo -e "  $0 list               Listar archivos en OneDrive"
    echo -e "  $0 health             Verificar salud del sistema"
    echo ""
    echo -e "${RED}DESINSTALACIÓN:${NC}"
    echo -e "  $0 remove             Quitar sincronización completamente"
    echo ""
    echo -e "${GREEN}EJEMPLOS:${NC}"
    echo -e "  $0 setup              # Primera configuración"
    echo -e "  $0 status             # Ver estado"
    echo -e "  $0 sync               # Sincronizar ahora"
    echo -e "  $0 logs 100           # Ver últimos 100 logs"
    echo -e "  $0 follow             # Seguir logs en vivo"
    echo -e "  $0 remove             # Quitar sincronización"
    echo ""
    echo -e "${GREEN}ARCHIVOS DE LOG:${NC}"
    echo -e "  ${PROJECT_ROOT}/logs/rclone-backup-sync.log"
    echo -e "  ${PROJECT_ROOT}/logs/rclone-config-sync.log"
    echo ""
    echo -e "${GREEN}COMANDOS SYSTEMD:${NC}"
    echo -e "  systemctl --user status ${BACKUP_SERVICE}.timer"
    echo -e "  journalctl --user -u ${BACKUP_SERVICE}.service -f"
    echo ""
}

# ============================================================================
# FUNCIÓN PRINCIPAL
# ============================================================================

# Setup completo
run_setup() {
    local reconfigure=${1:-false}

    clear
    header "🚀 OneDrive Sync Manager - Setup"
    echo ""

    check_system
    install_rclone

    if $reconfigure || ! check_existing_remote; then
        configure_onedrive_remote
    else
        info "Usando configuración existente de OneDrive"
    fi

    select_onedrive_folder
    create_backup_sync_service
    create_config_sync_service
    enable_systemd_services

    echo ""
    prompt "¿Ejecutar sincronización inicial ahora? (S/n): "
    read -r response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        run_initial_sync
    fi

    show_final_info
}

# Dispatcher de comandos
main() {
    # Manejar setup con --force
    if [[ "${1:-}" == "setup" && "${2:-}" == "--force" ]]; then
        run_setup true
        return
    fi

    case "${1:-help}" in
        setup)
            run_setup false
            ;;
        status|st)
            show_status
            ;;
        sync|sync-all)
            sync_now "$BACKUP_SERVICE" "backups"
            echo ""
            sync_now "$CONFIG_SERVICE" "config"
            ;;
        sync-backup|sync-backups)
            sync_now "$BACKUP_SERVICE" "backups"
            ;;
        sync-config)
            sync_now "$CONFIG_SERVICE" "config"
            ;;
        logs)
            show_logs "$BACKUP_SERVICE" "${2:-50}"
            ;;
        logs-config)
            show_logs "$CONFIG_SERVICE" "${2:-50}"
            ;;
        follow|tail)
            follow_logs "$BACKUP_SERVICE"
            ;;
        follow-config|tail-config)
            follow_logs "$CONFIG_SERVICE"
            ;;
        enable|start)
            toggle_services "enable"
            ;;
        disable|stop)
            toggle_services "disable"
            ;;
        restart|reload)
            log "Recargando servicios..."
            systemctl --user daemon-reload
            systemctl --user restart ${BACKUP_SERVICE}.timer
            systemctl --user restart ${CONFIG_SERVICE}.timer
            success "Servicios reiniciados"
            ;;
        list|ls)
            list_onedrive
            ;;
        health|check)
            check_health
            ;;
        remove|uninstall)
            remove_sync
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Comando desconocido: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Manejar señales de interrupción
trap 'error "Interrumpido"; exit 130' INT TERM

# Ejecutar
main "$@"


