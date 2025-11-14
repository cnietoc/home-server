#!/usr/bin/env bash
# ============================================
# lib/state.sh — Librería de gestión de estado del servidor
# Proporciona funciones para consultar y actualizar el estado de deployments
# ============================================

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente." >&2
    exit 1
}

# --- Inicialización de variables ---
_STATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_STATE_PROJECT_ROOT="$(dirname "$_STATE_LIB_DIR")"
_STATE_FILE="${_STATE_PROJECT_ROOT}/data/state.yml"

# Cargar dependencias desde lib/
source "${_STATE_LIB_DIR}/logs.sh"
source "${_STATE_LIB_DIR}/yq.sh"
source "${_STATE_LIB_DIR}/stack.sh"

# ============================================
# FUNCIONES DE INICIALIZACIÓN
# ============================================

# Inicializar archivo de estado si no existe
state::init() {
    if [[ -f "$_STATE_FILE" ]]; then
        return 0
    fi

    log::info "📝 Creando archivo de estado inicial: $_STATE_FILE"

    # Crear directorio si no existe
    mkdir -p "$(dirname "$_STATE_FILE")"

    # Obtener lista de stacks
    local all_stacks
    all_stacks=$(stack::list)
    if [[ -z "$all_stacks" ]]; then
        logs::error "No se pudieron obtener los stacks disponibles"
        return 1
    fi

    # Crear estructura inicial directamente en bash (sin yq)
    cat > "$_STATE_FILE" << 'EOF'
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
    while IFS= read -r stack; do
        [[ -z "$stack" ]] && continue
        cat >> "$_STATE_FILE" << EOF
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

# ============================================
# FUNCIONES DE CONSULTA - STACKS
# ============================================

# Verificar si un stack está habilitado
state::stack::is_enabled() {
    local stack="$1"
    if [[ ! -f "$_STATE_FILE" ]]; then
        # Si no existe el archivo, asumir que está habilitado
        return 0
    fi

    local enabled
    enabled=$(yq_read ".stacks.${stack}.enabled" "$_STATE_FILE" 2>/dev/null)

    # Si es null, vacío o true, está habilitado
    if [[ -z "$enabled" || "$enabled" == "null" || "$enabled" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Obtener lista de stacks habilitados
state::stack::list_enabled() {
    if [[ ! -f "$_STATE_FILE" ]]; then
        # Si no existe el archivo, devolver todos los stacks
        stack::list
        return 0
    fi

    yq_read '.stacks | to_entries | map(select(.value.enabled == true)) | .[].key' "$_STATE_FILE"
}

# Obtener lista de stacks deshabilitados
state::stack::list_disabled() {
    if [[ ! -f "$_STATE_FILE" ]]; then
        return 0
    fi

    yq_read '.stacks | to_entries | map(select(.value.enabled == false)) | .[].key' "$_STATE_FILE"
}

# Obtener hash de último deployment de un stack
state::stack::get_deployment_hash() {
    local stack="$1"
    if [[ ! -f "$_STATE_FILE" ]]; then
        echo ""
        return 0
    fi

    local hash
    hash=$(yq_read ".stacks.${stack}.last_deployment.hash" "$_STATE_FILE" 2>/dev/null)

    # Si es null o vacío, devolver vacío
    if [[ -z "$hash" || "$hash" == "null" ]]; then
        echo ""
    else
        echo "$hash"
    fi
}

# Habilitar un stack
state::stack::enable() {
    local stack="$1"
    state::init || return 1

    yq_write ".stacks.${stack}.enabled = true" "$_STATE_FILE"
    yq_write "del(.stacks.${stack}.disabled_at)" "$_STATE_FILE"
    yq_write "del(.stacks.${stack}.disabled_reason)" "$_STATE_FILE"

    log "✅ Stack '$stack' habilitado"
    return 0
}

# Deshabilitar un stack
state::stack::disable() {
    local stack="$1"
    local reason="${2:-No especificado}"

    state::init || return 1

    local timestamp=$(date -Iseconds)
    yq_write ".stacks.${stack}.enabled = false" "$_STATE_FILE"
    yq_write ".stacks.${stack}.disabled_at = \"$timestamp\"" "$_STATE_FILE"
    yq_write ".stacks.${stack}.disabled_reason = \"$reason\"" "$_STATE_FILE"

    log "❌ Stack '$stack' deshabilitado"
    log "   Motivo: $reason"
    return 0
}

# Actualizar hash de deployment de un stack
state::stack::update_deployment() {
    local stack="$1"
    local hash="$2"

    state::init || return 1

    local timestamp=$(date +%s)
    local date=$(date -Iseconds)

    yq_write ".stacks.${stack}.last_deployment.timestamp = $timestamp" "$_STATE_FILE"
    yq_write ".stacks.${stack}.last_deployment.date = \"$date\"" "$_STATE_FILE"
    yq_write ".stacks.${stack}.last_deployment.hash = \"$hash\"" "$_STATE_FILE"

    return 0
}

# ============================================
# FUNCIONES DE CONSULTA - SERVIDOR
# ============================================

# Obtener hash global de configuración
state::server::get_config_hash() {
    if [[ ! -f "$_STATE_FILE" ]]; then
        echo ""
        return 0
    fi

    local hash
    hash=$(yq_read ".server.config_hash" "$_STATE_FILE" 2>/dev/null)

    # Si es null o vacío, devolver vacío
    if [[ -z "$hash" || "$hash" == "null" ]]; then
        echo ""
    else
        echo "$hash"
    fi
}

# Obtener timestamp del último deployment global
state::server::get_last_deployment_timestamp() {
    if [[ ! -f "$_STATE_FILE" ]]; then
        echo "0"
        return 0
    fi

    local timestamp
    timestamp=$(yq_read ".server.last_deployment.timestamp" "$_STATE_FILE" 2>/dev/null)

    # Si es null o vacío, devolver 0
    if [[ -z "$timestamp" || "$timestamp" == "null" ]]; then
        echo "0"
    else
        echo "$timestamp"
    fi
}

# Obtener fecha del último deployment global
state::server::get_last_deployment_date() {
    if [[ ! -f "$_STATE_FILE" ]]; then
        echo "never"
        return 0
    fi

    local date
    date=$(yq_read ".server.last_deployment.date" "$_STATE_FILE" 2>/dev/null)

    # Si es null o vacío, devolver "never"
    if [[ -z "$date" || "$date" == "null" ]]; then
        echo "never"
    else
        echo "$date"
    fi
}

# Actualizar hash global de configuración
state::server::update_config_hash() {
    local hash="$1"
    state::init || return 1

    yq_write ".server.config_hash = \"$hash\"" "$_STATE_FILE"
    return 0
}

# Actualizar timestamp global de deployment
state::server::update_deployment() {
    state::init || return 1

    local timestamp=$(date +%s)
    local date=$(date -Iseconds)

    yq_write ".server.last_deployment.timestamp = $timestamp" "$_STATE_FILE"
    yq_write ".server.last_deployment.date = \"$date\"" "$_STATE_FILE"

    return 0
}

# ============================================
# FUNCIONES DE MANTENIMIENTO
# ============================================

# Actualizar estado de mantenimiento
state::maintenance::update_status() {
    local task="$1"      # daily, weekly
    local status="$2"    # success, failed, running

    state::init || return 1

    local timestamp=$(date +%s)
    local date=$(date -Iseconds)

    yq_write ".server.maintenance.${task}.last_run.timestamp = $timestamp" "$_STATE_FILE"
    yq_write ".server.maintenance.${task}.last_run.date = \"$date\"" "$_STATE_FILE"
    yq_write ".server.maintenance.${task}.status = \"$status\"" "$_STATE_FILE"

    return 0
}

# Obtener último estado de mantenimiento
state::maintenance::get_status() {
    local task="$1"  # daily, weekly

    if [[ ! -f "$_STATE_FILE" ]]; then
        echo "never"
        return 0
    fi

    local status
    status=$(yq_read ".server.maintenance.${task}.status" "$_STATE_FILE" 2>/dev/null)

    if [[ -z "$status" || "$status" == "null" ]]; then
        echo "never"
    else
        echo "$status"
    fi
}

# Obtener fecha de último mantenimiento
state::maintenance::get_last_run() {
    local task="$1"  # daily, weekly

    if [[ ! -f "$_STATE_FILE" ]]; then
        echo "never"
        return 0
    fi

    local date
    date=$(yq_read ".server.maintenance.${task}.last_run.date" "$_STATE_FILE" 2>/dev/null)

    if [[ -z "$date" || "$date" == "null" ]]; then
        echo "never"
    else
        echo "$date"
    fi
}

# ============================================
# FUNCIONES DE VISUALIZACIÓN
# ============================================

# Mostrar estado general
state::show_status() {
    if [[ ! -f "$_STATE_FILE" ]]; then
        log "ℹ️  No hay archivo de estado. Ejecuta un deployment primero."
        return 0
    fi

    log "📊 Estado del Home Server"
    echo ""

    # Estado global
    local last_timestamp=$(state::server::get_last_deployment_timestamp)
    local last_date=$(state::server::get_last_deployment_date)

    log "🌐 Último deployment:"
    if [[ "$last_timestamp" != "0" ]]; then
        local hours_ago=$(( ($(date +%s) - last_timestamp) / 3600 ))
        log "   Hace ${hours_ago}h - $last_date"
    else
        log "   Nunca"
    fi

    echo ""
    log "📦 Stacks:"

    # Listar stacks habilitados
    local enabled_stacks=$(state::stack::list_enabled)
    local enabled_count=0
    if [[ -n "$enabled_stacks" ]]; then
        enabled_count=$(echo "$enabled_stacks" | wc -l | tr -d ' ')
    fi

    log "   ✅ Habilitados: $enabled_count"
    if [[ "$enabled_count" -gt 0 ]]; then
        while IFS= read -r stack; do
            [[ -z "$stack" ]] && continue
            log "      - $stack"
        done <<< "$enabled_stacks"
    fi

    # Listar stacks deshabilitados
    local disabled_stacks=$(state::stack::list_disabled)
    local disabled_count=0
    if [[ -n "$disabled_stacks" ]]; then
        disabled_count=$(echo "$disabled_stacks" | wc -l | tr -d ' ')
    fi

    if [[ "$disabled_count" -gt 0 ]]; then
        echo ""
        log "   ❌ Deshabilitados: $disabled_count"
        while IFS= read -r stack; do
            [[ -z "$stack" ]] && continue
            local reason=$(yq_read ".stacks.${stack}.disabled_reason" "$_STATE_FILE" 2>/dev/null)
            log "      - $stack ($reason)"
        done <<< "$disabled_stacks"
    fi
}
