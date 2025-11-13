#!/usr/bin/env bash

# Script para gestionar el estado del Home Server
# Maneja el archivo data/state.yml con información de despliegues y configuración

set -uo pipefail

STATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PROJECT_ROOT="$(dirname "$STATE_SCRIPT_DIR")"
STATE_FILE="$STATE_PROJECT_ROOT/data/state.yml"

# Cargar stack-info para obtener lista de stacks
source "$STATE_SCRIPT_DIR/stack-info.sh" || {
    echo "❌ Error: No se pudo cargar stack-info.sh" >&2
    exit 1
}

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    log "❌ $*" >&2
}

# Verificar que yq está instalado
check_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        error "yq no está instalado. Instálalo con:"
        error "  - Ubuntu/Debian: sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq"
        error "  - macOS: brew install yq"
        error "  - Fedora/RHEL: sudo dnf install yq"
        return 1
    fi
    return 0
}

# Inicializar archivo de estado si no existe
init_state_file() {
    if [[ -f "$STATE_FILE" ]]; then
        return 0
    fi

    log "📝 Creando archivo de estado inicial: $STATE_FILE"

    # Crear directorio si no existe
    mkdir -p "$(dirname "$STATE_FILE")"

    # Inicializar stack-info para obtener lista de stacks
    if ! init_stack_info; then
        error "No se pudo inicializar stack-info"
        return 1
    fi

    # Crear estructura inicial
    cat > "$STATE_FILE" << 'EOF'
# data/state.yml - Estado de despliegue del Home Server
# Este archivo NO se versiona en Git - es estado local del servidor

# Información global del servidor
server:
  last_deployment:
    timestamp: 0
    date: "never"
  config_hash: ""
  maintenance:
    daily:
      last_run:
        timestamp: 0
        date: "never"
      status: "never"
    weekly:
      last_run:
        timestamp: 0
        date: "never"
      status: "never"

# Estado de cada stack
stacks: {}
EOF

    # Añadir cada stack conocido con estado inicial
    local all_stacks
    all_stacks=$(get_available_stacks)

    if [[ -z "$all_stacks" ]]; then
        error "No se pudieron obtener los stacks disponibles"
        return 1
    fi

    while IFS= read -r stack; do
        [[ -z "$stack" ]] && continue

        yq -i ".stacks.${stack}.enabled = true" "$STATE_FILE"
        yq -i ".stacks.${stack}.last_deployment.timestamp = 0" "$STATE_FILE"
        yq -i ".stacks.${stack}.last_deployment.date = \"never\"" "$STATE_FILE"
        yq -i ".stacks.${stack}.last_deployment.hash = \"\"" "$STATE_FILE"
        # No añadir disabled_at ni disabled_reason - solo aparecen cuando está deshabilitado
    done <<< "$all_stacks"

    log "✅ Archivo de estado inicializado con $(echo "$all_stacks" | wc -l) stacks"
    return 0
}

# Verificar si un stack está habilitado
is_stack_enabled() {
    local stack=$1

    if ! check_yq; then
        return 1
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        # Si no existe el archivo, asumir que está habilitado
        return 0
    fi

    local enabled
    enabled=$(yq ".stacks.${stack}.enabled // true" "$STATE_FILE" 2>/dev/null)

    [[ "$enabled" == "true" ]]
}

# Habilitar un stack
enable_stack() {
    local stack=$1

    if ! check_yq; then
        return 1
    fi

    init_state_file || return 1

    yq -i ".stacks.${stack}.enabled = true" "$STATE_FILE"
    yq -i "del(.stacks.${stack}.disabled_at)" "$STATE_FILE"
    yq -i "del(.stacks.${stack}.disabled_reason)" "$STATE_FILE"

    log "✅ Stack '$stack' habilitado"
    return 0
}

# Deshabilitar un stack
disable_stack() {
    local stack=$1
    local reason=${2:-"No especificado"}

    if ! check_yq; then
        return 1
    fi

    init_state_file || return 1

    local timestamp=$(date -Iseconds)

    yq -i ".stacks.${stack}.enabled = false" "$STATE_FILE"
    yq -i ".stacks.${stack}.disabled_at = \"$timestamp\"" "$STATE_FILE"
    yq -i ".stacks.${stack}.disabled_reason = \"$reason\"" "$STATE_FILE"

    log "❌ Stack '$stack' deshabilitado"
    log "   Motivo: $reason"
    return 0
}

# Obtener lista de stacks habilitados
get_enabled_stacks() {
    if ! check_yq; then
        return 1
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        # Si no existe el archivo, devolver todos los stacks
        get_available_stacks
        return 0
    fi

    yq '.stacks | to_entries | map(select(.value.enabled == true)) | .[].key' "$STATE_FILE"
}

# Obtener lista de stacks deshabilitados
get_disabled_stacks() {
    if ! check_yq; then
        return 1
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        return 0
    fi

    yq '.stacks | to_entries | map(select(.value.enabled == false)) | .[].key' "$STATE_FILE"
}

# Actualizar hash de deployment de un stack
update_stack_deployment() {
    local stack=$1
    local hash=$2

    if ! check_yq; then
        return 1
    fi

    init_state_file || return 1

    local timestamp=$(date +%s)
    local date=$(date -Iseconds)

    yq -i ".stacks.${stack}.last_deployment.timestamp = $timestamp" "$STATE_FILE"
    yq -i ".stacks.${stack}.last_deployment.date = \"$date\"" "$STATE_FILE"
    yq -i ".stacks.${stack}.last_deployment.hash = \"$hash\"" "$STATE_FILE"

    return 0
}

# Actualizar hash global de configuración
update_config_hash() {
    local hash=$1

    if ! check_yq; then
        return 1
    fi

    init_state_file || return 1

    yq -i ".server.config_hash = \"$hash\"" "$STATE_FILE"

    return 0
}

# Actualizar timestamp global de deployment
update_global_deployment() {
    if ! check_yq; then
        return 1
    fi

    init_state_file || return 1

    local timestamp=$(date +%s)
    local date=$(date -Iseconds)

    yq -i ".server.last_deployment.timestamp = $timestamp" "$STATE_FILE"
    yq -i ".server.last_deployment.date = \"$date\"" "$STATE_FILE"

    return 0
}

# Actualizar estado de mantenimiento
update_maintenance_status() {
    local task=$1      # daily, weekly
    local status=$2    # success, failed, running

    if ! check_yq; then
        return 1
    fi

    init_state_file || return 1

    local timestamp=$(date +%s)
    local date=$(date -Iseconds)

    yq -i ".server.maintenance.${task}.last_run.timestamp = $timestamp" "$STATE_FILE"
    yq -i ".server.maintenance.${task}.last_run.date = \"$date\"" "$STATE_FILE"
    yq -i ".server.maintenance.${task}.status = \"$status\"" "$STATE_FILE"

    return 0
}

# Obtener hash de último deployment de un stack
get_stack_deployment_hash() {
    local stack=$1

    if ! check_yq; then
        return 1
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return 0
    fi

    yq ".stacks.${stack}.last_deployment.hash // \"\"" "$STATE_FILE"
}

# Obtener hash global de configuración
get_config_hash() {
    if ! check_yq; then
        return 1
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return 0
    fi

    yq ".server.config_hash // \"\"" "$STATE_FILE"
}

# Exportar funciones para que puedan ser usadas por otros scripts
export -f is_stack_enabled
export -f enable_stack
export -f disable_stack
export -f get_enabled_stacks
export -f get_disabled_stacks
export -f update_stack_deployment
export -f update_config_hash
export -f update_global_deployment
export -f update_maintenance_status
export -f get_stack_deployment_hash
export -f get_config_hash
export -f init_state_file

