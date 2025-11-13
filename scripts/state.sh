#!/usr/bin/env bash
# Script para gestionar el estado de despliegue del Home Server
# Maneja el archivo data/state.yml con información de deployments y estado de stacks
set -euo pipefail
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
    # Obtener lista de stacks
    local all_stacks
    all_stacks=$("$STATE_SCRIPT_DIR/stack-info.sh" get_available_stacks)
    if [[ -z "$all_stacks" ]]; then
        error "No se pudieron obtener los stacks disponibles"
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
# === Funciones de Lectura de Estado ===
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
# Obtener lista de stacks habilitados
get_enabled_stacks() {
    if [[ ! -f "$STATE_FILE" ]]; then
        # Si no existe el archivo, devolver todos los stacks
        "$STATE_SCRIPT_DIR/stack-info.sh" get_available_stacks
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
# === Funciones de Escritura de Estado ===
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
# === Comandos de Visualización ===
# Mostrar estado general
show_status() {
    if [[ ! -f "$STATE_FILE" ]]; then
        log "ℹ️  No hay archivo de estado. Ejecuta un deployment primero."
        return 0
    fi
    log "📊 Estado del Home Server"
    echo ""
    # Estado global
    local last_timestamp=$(get_last_deployment_timestamp)
    local last_date=$(get_last_deployment_date)
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
    local enabled_stacks=$(get_enabled_stacks)
    local enabled_count=$(echo "$enabled_stacks" | grep -c . || echo "0")
    log "   ✅ Habilitados: $enabled_count"
    if [[ "$enabled_count" -gt 0 ]]; then
        while IFS= read -r stack; do
            [[ -z "$stack" ]] && continue
            log "      - $stack"
        done <<< "$enabled_stacks"
    fi
    # Listar stacks deshabilitados
    local disabled_stacks=$(get_disabled_stacks)
    local disabled_count=$(echo "$disabled_stacks" | grep -c . || echo "0")
    if [[ "$disabled_count" -gt 0 ]]; then
        echo ""
        log "   ❌ Deshabilitados: $disabled_count"
        while IFS= read -r stack; do
            [[ -z "$stack" ]] && continue
            local reason=$(run_yq ".stacks.${stack}.disabled_reason" "$STATE_FILE" 2>/dev/null)
            log "      - $stack ($reason)"
        done <<< "$disabled_stacks"
    fi
}
# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $0 [comando] [opciones]
DESCRIPCIÓN:
  Script centralizado para gestionar el estado de despliegue del Home Server.
  Maneja el archivo data/state.yml con información de deployments y estado de stacks.
COMANDOS PRINCIPALES:
  status                         - Mostrar estado general del servidor
  enable [stack]                 - Habilitar un stack
  disable [stack] [motivo]       - Deshabilitar un stack con motivo
  init                          - Inicializar archivo de estado
  help                          - Mostrar esta ayuda
COMANDOS WRAPPER (para otros scripts):
  # Lectura de estado:
  is_stack_enabled [stack]       - Verificar si un stack está habilitado (exit code)
  get_enabled_stacks             - Obtener lista de stacks habilitados
  get_disabled_stacks            - Obtener lista de stacks deshabilitados
  get_stack_deployment_hash [stack] - Obtener hash del último deployment
  get_config_hash                - Obtener hash global de configuración
  get_last_deployment_timestamp  - Obtener timestamp del último deployment
  get_last_deployment_date       - Obtener fecha del último deployment
  # Escritura de estado:
  update_stack_deployment [stack] [hash] - Actualizar deployment de un stack
  update_config_hash [hash]      - Actualizar hash global de configuración
  update_global_deployment       - Actualizar timestamp global
  update_maintenance_status [task] [status] - Actualizar estado de mantenimiento
EJEMPLOS:
  $0 status                      # Ver estado general
  $0 enable platform             # Habilitar stack platform
  $0 disable media "Mantenimiento de discos"  # Deshabilitar con motivo
  # Uso desde otros scripts:
  $0 is_stack_enabled platform && echo "habilitado"
  $0 get_enabled_stacks          # Lista de stacks habilitados
  $0 update_stack_deployment platform abc123  # Actualizar hash
ARCHIVO DE ESTADO:
  $STATE_FILE
ESTRUCTURA DEL ARCHIVO (YAML):
  server:
    last_deployment:
      timestamp: 1234567890
      date: "2025-11-13T10:00:00Z"
    config_hash: "abc123..."
    maintenance:
      daily:
        last_run: {...}
        status: "success"
      weekly:
        last_run: {...}
        status: "success"
  stacks:
    stack_name:
      enabled: true/false
      last_deployment:
        timestamp: 1234567890
        date: "2025-11-13T10:00:00Z"
        hash: "abc123..."
      disabled_at: "2025-11-13T10:00:00Z"  # Solo si está deshabilitado
      disabled_reason: "Motivo"             # Solo si está deshabilitado
NOTAS:
  - El archivo se crea automáticamente si no existe
  - Los campos disabled_at y disabled_reason solo aparecen cuando está deshabilitado
  - Este script es el único punto de acceso al archivo de estado desde otros scripts
DEPENDENCIAS:
  - yq (mikefarah/yq versión Go)
  - stack-info.sh (para obtener lista de stacks disponibles)
EOF
}
# Función principal
main() {
    case "${1:-help}" in
        "status")
            show_status
            ;;
        "enable")
            if [[ -z "${2:-}" ]]; then
                error "Especifica un stack"
                echo "Uso: $0 enable [stack_name]"
                exit 1
            fi
            enable_stack "$2"
            ;;
        "disable")
            if [[ -z "${2:-}" ]]; then
                error "Especifica un stack"
                echo "Uso: $0 disable [stack_name] [motivo]"
                exit 1
            fi
            disable_stack "$2" "${3:-No especificado}"
            ;;
        "init")
            init_state_file
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        # Comandos wrapper para otros scripts - Lectura
        "is_stack_enabled")
            if [[ -z "${2:-}" ]]; then
                exit 1
            fi
            is_stack_enabled "$2"
            ;;
        "get_enabled_stacks")
            get_enabled_stacks
            ;;
        "get_disabled_stacks")
            get_disabled_stacks
            ;;
        "get_stack_deployment_hash")
            if [[ -z "${2:-}" ]]; then
                exit 1
            fi
            get_stack_deployment_hash "$2"
            ;;
        "get_config_hash")
            get_config_hash
            ;;
        "get_last_deployment_timestamp")
            get_last_deployment_timestamp
            ;;
        "get_last_deployment_date")
            get_last_deployment_date
            ;;
        # Comandos wrapper para otros scripts - Escritura
        "update_stack_deployment")
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                exit 1
            fi
            update_stack_deployment "$2" "$3"
            ;;
        "update_config_hash")
            if [[ -z "${2:-}" ]]; then
                exit 1
            fi
            update_config_hash "$2"
            ;;
        "update_global_deployment")
            update_global_deployment
            ;;
        "update_maintenance_status")
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                exit 1
            fi
            update_maintenance_status "$2" "$3"
            ;;
        "init_state_file")
            init_state_file
            ;;
        *)
            echo "❌ Comando desconocido: ${1:-}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}
# Solo ejecutar main si el script se ejecuta directamente, no si se hace source
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
