#!/usr/bin/env bash

# Script para gestionar el estado del Home Server
# Maneja el archivo data/state.yml con información de despliegues y configuración

set -uo pipefail

STATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PROJECT_ROOT="$(dirname "$STATE_SCRIPT_DIR")"
STATE_FILE="$STATE_PROJECT_ROOT/data/state.yml"

# Cargar yq-helper para funciones de yq
source "$STATE_SCRIPT_DIR/common/yq-helper.sh" || {
    echo "❌ Error: No se pudo cargar yq-helper.sh" >&2
    exit 1
}

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

    # Crear estructura inicial directamente en bash (sin yq)
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
stacks:
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

        cat >> "$STATE_FILE" << EOF
  ${stack}:
    enabled: true
    last_deployment:
      timestamp: 0
      date: "never"
      hash: ""
EOF
    done <<< "$all_stacks"

    log "✅ Archivo de estado inicializado con $(echo "$all_stacks" | wc -l | tr -d ' ') stacks"
    return 0
}

# Verificar si un stack está habilitado
# Verificar si un stack está habilitado
is_stack_enabled() {
    local stack=$1

    if [[ ! -f "$STATE_FILE" ]]; then
        # Si no existe el archivo, asumir que está habilitado
        return 0
    fi

    local enabled
    enabled=$(run_yq ".stacks.${stack}.enabled" "$STATE_FILE" 2>/dev/null)

    # Si es null, vacío o true, está habilitado
    if [[ -z "$enabled" || "$enabled" == "null" || "$enabled" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Habilitar un stack
enable_stack() {
    local stack=$1


    init_state_file || return 1

    run_yq_inplace ".stacks.${stack}.enabled = true" "$STATE_FILE"
    run_yq_inplace "del(.stacks.${stack}.disabled_at)" "$STATE_FILE"
    run_yq_inplace "del(.stacks.${stack}.disabled_reason)" "$STATE_FILE"

    log "✅ Stack '$stack' habilitado"
    return 0
}

# Deshabilitar un stack
disable_stack() {
    local stack=$1
    local reason=${2:-"No especificado"}


    init_state_file || return 1

    local timestamp=$(date -Iseconds)

    run_yq_inplace ".stacks.${stack}.enabled = false" "$STATE_FILE"
    run_yq_inplace ".stacks.${stack}.disabled_at = \"$timestamp\"" "$STATE_FILE"
    run_yq_inplace ".stacks.${stack}.disabled_reason = \"$reason\"" "$STATE_FILE"

    log "❌ Stack '$stack' deshabilitado"
    log "   Motivo: $reason"
    return 0
}

# Obtener lista de stacks habilitados
get_enabled_stacks() {
    if [[ ! -f "$STATE_FILE" ]]; then
        # Si no existe el archivo, devolver todos los stacks
        get_available_stacks
        return 0
    fi

    run_yq '.stacks | to_entries | map(select(.value.enabled == true)) | .[].key' "$STATE_FILE"
}

# Obtener lista de stacks deshabilitados
get_disabled_stacks() {
    if [[ ! -f "$STATE_FILE" ]]; then
        return 0
    fi

    run_yq '.stacks | to_entries | map(select(.value.enabled == false)) | .[].key' "$STATE_FILE"
}

# Actualizar hash de deployment de un stack
update_stack_deployment() {
    local stack=$1
    local hash=$2


    init_state_file || return 1

    local timestamp=$(date +%s)
    local date=$(date -Iseconds)

    run_yq_inplace ".stacks.${stack}.last_deployment.timestamp = $timestamp" "$STATE_FILE"
    run_yq_inplace ".stacks.${stack}.last_deployment.date = \"$date\"" "$STATE_FILE"
    run_yq_inplace ".stacks.${stack}.last_deployment.hash = \"$hash\"" "$STATE_FILE"

    return 0
}

# Actualizar hash global de configuración
update_config_hash() {
    local hash=$1


    init_state_file || return 1

    run_yq_inplace ".server.config_hash = \"$hash\"" "$STATE_FILE"

    return 0
}

# Actualizar timestamp global de deployment
update_global_deployment() {

    init_state_file || return 1

    local timestamp=$(date +%s)
    local date=$(date -Iseconds)

    run_yq_inplace ".server.last_deployment.timestamp = $timestamp" "$STATE_FILE"
    run_yq_inplace ".server.last_deployment.date = \"$date\"" "$STATE_FILE"

    return 0
}

# Actualizar estado de mantenimiento
update_maintenance_status() {
    local task=$1      # daily, weekly
    local status=$2    # success, failed, running


    init_state_file || return 1

    local timestamp=$(date +%s)
    local date=$(date -Iseconds)

    run_yq_inplace ".server.maintenance.${task}.last_run.timestamp = $timestamp" "$STATE_FILE"
    run_yq_inplace ".server.maintenance.${task}.last_run.date = \"$date\"" "$STATE_FILE"
    run_yq_inplace ".server.maintenance.${task}.status = \"$status\"" "$STATE_FILE"

    return 0
}

# Obtener hash de último deployment de un stack
get_stack_deployment_hash() {
    local stack=$1

    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return 0
    fi

    local hash
    hash=$(run_yq ".stacks.${stack}.last_deployment.hash" "$STATE_FILE" 2>/dev/null)

    # Si es null o vacío, devolver vacío
    if [[ -z "$hash" || "$hash" == "null" ]]; then
        echo ""
    else
        echo "$hash"
    fi
}

# Obtener hash global de configuración
get_config_hash() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo ""
        return 0
    fi

    local hash
    hash=$(run_yq ".server.config_hash" "$STATE_FILE" 2>/dev/null)

    # Si es null o vacío, devolver vacío
    if [[ -z "$hash" || "$hash" == "null" ]]; then
        echo ""
    else
        echo "$hash"
    fi
}

# Obtener timestamp del último deployment global
get_last_deployment_timestamp() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "0"
        return 0
    fi

    local timestamp
    timestamp=$(run_yq ".server.last_deployment.timestamp" "$STATE_FILE" 2>/dev/null)

    # Si es null o vacío, devolver 0
    if [[ -z "$timestamp" || "$timestamp" == "null" ]]; then
        echo "0"
    else
        echo "$timestamp"
    fi
}

# Obtener fecha del último deployment global
get_last_deployment_date() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "never"
        return 0
    fi

    local date
    date=$(run_yq ".server.last_deployment.date" "$STATE_FILE" 2>/dev/null)

    # Si es null o vacío, devolver "never"
    if [[ -z "$date" || "$date" == "null" ]]; then
        echo "never"
    else
        echo "$date"
    fi
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
export -f get_last_deployment_timestamp
export -f get_last_deployment_date
export -f init_state_file

