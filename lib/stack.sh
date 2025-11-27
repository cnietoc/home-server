#!/usr/bin/env bash
# ============================================
# lib/stack.sh — Librería de gestión de stacks
# Proporciona funciones para consultar configuración de stacks desde YAML
# ============================================

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente." >&2
    exit 1
}

# --- Inicialización de variables ---
_STACK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_STACK_PROJECT_ROOT="$(dirname "$_STACK_LIB_DIR")"
_STACK_CONFIG_FILE="${_STACK_PROJECT_ROOT}/config/stacks.yml"

# Cargar dependencias desde lib/
source "${_STACK_LIB_DIR}/env.sh"
source "${_STACK_LIB_DIR}/yq.sh"

# ============================================
# FUNCIONES DE CONSULTA BÁSICA
# ============================================

# Listar todos los stacks disponibles
stack::list() {
    yq::read '.stacks | keys | .[]' "$_STACK_CONFIG_FILE"
}

# Verificar si un stack existe
stack::exists() {
    local stack_name="$1"
    [[ ! -f "$_STACK_CONFIG_FILE" ]] && return 1

    local exists
    exists=$(yq::read ".stacks | has(\"$stack_name\")" "$_STACK_CONFIG_FILE" 2>/dev/null)
    [[ "$exists" == "true" ]]
}

# Obtener descripción de un stack
stack::get_description() {
    local stack_name="$1"
    local desc
    desc=$(yq::read ".stacks.$stack_name.description" "$_STACK_CONFIG_FILE" 2>/dev/null)
    [[ "$desc" == "null" ]] && echo "" || echo "$desc"
}

# ============================================
# FUNCIONES DE CONFIGURACIÓN
# ============================================

# Obtener archivos de configuración de un stack (siempre incluye 'common')
stack::get_config_files() {
    local stack_name="$1"
    local config_files
    config_files=$(yq::read ".stacks.$stack_name.config_files | join(\",\")" "$_STACK_CONFIG_FILE")

    if [[ "$config_files" == "null" || -z "$config_files" ]]; then
        echo "common"
    else
        echo "common,$config_files"
    fi
}

# ============================================
# FUNCIONES DE SERVICIOS
# ============================================

# Obtener todos los servicios de un stack
stack::service::list() {
    local stack_name="$1"
    yq::read ".stacks.$stack_name.services | keys | .[]" "$_STACK_CONFIG_FILE" 2>/dev/null || true
}


# Obtener subdomain de un servicio específico
stack::service::get_subdomain() {
    local stack_name="$1"
    local service_name="$2"
    local subdomain
    subdomain=$(yq::read ".stacks.$stack_name.services.$service_name.subdomain" "$_STACK_CONFIG_FILE" 2>/dev/null)
    [[ "$subdomain" == "null" ]] && echo "" || echo "$subdomain"
}

# Obtener descripción de un servicio
stack::service::get_description() {
    local stack_name="$1"
    local service_name="$2"
    local desc
    desc=$(yq::read ".stacks.$stack_name.services.$service_name.description" "$_STACK_CONFIG_FILE" 2>/dev/null)
    [[ "$desc" == "null" ]] && echo "" || echo "$desc"
}

# Construir URL completa desde subdomain
stack::service::build_url() {
    local subdomain="$1"
    local base_domain="tu-dominio.com"

    # Intentar cargar BASE_DOMAIN del entorno
    if load_common_config 2>/dev/null && [[ -n "${BASE_DOMAIN:-}" ]]; then
        base_domain="$BASE_DOMAIN"
    fi

    if [[ -z "$subdomain" ]]; then
        echo "https://${base_domain}"
    else
        echo "https://${subdomain}.${base_domain}"
    fi
}

# ============================================
# FUNCIONES DE SHARES (NFS/Samba)
# ============================================

# Listar stacks que tienen configuración de shares
stack::shares::list_stacks() {
    yq::read '.stacks | to_entries | .[] | select(.value.shares) | .key' "$_STACK_CONFIG_FILE" 2>/dev/null || true
}

# Listar shares de un stack
stack::shares::list() {
    local stack_name="$1"
    yq::read ".stacks.$stack_name.shares | keys | .[]" "$_STACK_CONFIG_FILE" 2>/dev/null || true
}

# Obtener información de un share
stack::shares::get_field() {
    local stack_name="$1"
    local share_name="$2"
    local field="$3"  # path, exposed_path, description, permissions

    local value
    value=$(yq::read ".stacks.$stack_name.shares.$share_name.$field" "$_STACK_CONFIG_FILE" 2>/dev/null)
    [[ "$value" == "null" ]] && echo "" || echo "$value"
}

# Obtener path de un share
stack::shares::get_path() {
    local stack_name="$1"
    local share_name="$2"
    local raw_path
    raw_path=$(stack::shares::get_field "$stack_name" "$share_name" "path")
    stack::shares::resolve_path "$raw_path" "$stack_name"
}

# Resolver path de un share (convertir relativo a absoluto)
stack::shares::resolve_path() {
    local path="$1"
    local stack_name="$2"

    # Si es path absoluto fuera del proyecto, dejarlo como está
    if [[ "$path" =~ ^/data/ || "$path" =~ ^/home/ || "$path" =~ ^/var/ || "$path" =~ ^/opt/ ]]; then
        echo "$path"
        return
    fi

    # Path relativo al directorio de datos
    local relative_path="${path#/}"
    echo "${_STACK_PROJECT_ROOT}/data/media/${relative_path}"
}

# Obtener exposed_path de un share (con fallback al path real)
stack::shares::get_exposed_path() {
    local stack_name="$1"
    local share_name="$2"
    local exposed_path
    exposed_path=$(stack::shares::get_field "$stack_name" "$share_name" "exposed_path")

    if [[ -z "$exposed_path" ]]; then
        stack::shares::get_path "$stack_name" "$share_name"
    else
        echo "$exposed_path"
    fi
}

# Obtener descripción de un share
stack::shares::get_description() {
    local stack_name="$1"
    local share_name="$2"
    stack::shares::get_field "$stack_name" "$share_name" "description"
}

# Obtener permisos de un share
stack::shares::get_permissions() {
    local stack_name="$1"
    local share_name="$2"
    stack::shares::get_field "$stack_name" "$share_name" "permissions"
}

# ============================================
# FUNCIONES DE BACKUP
# ============================================

# Listar stacks que tienen configuración de backup
stack::backup::list_stacks() {
    yq::read '.stacks | to_entries | .[] | select(.value.backups) | .key' "$_STACK_CONFIG_FILE" 2>/dev/null || true
}

# Verificar si un stack tiene configuración de backup
stack::backup::has_config() {
    local stack_name="$1"
    local backup_config
    backup_config=$(yq::read ".stacks.$stack_name.backups" "$_STACK_CONFIG_FILE" 2>/dev/null)
    [[ "$backup_config" != "null" && -n "$backup_config" ]]
}

# Obtener exclusiones de backup de un stack
stack::backup::get_exclusions() {
    local stack_name="$1"
    stack::backup::has_config "$stack_name" || return 0
    yq::read ".stacks.$stack_name.backups.exclude | .[]" "$_STACK_CONFIG_FILE" 2>/dev/null || true
}

# Obtener configuración completa de backup
stack::backup::get_config() {
    local stack_name="$1"
    stack::backup::has_config "$stack_name" || { echo "null"; return 0; }
    yq::read ".stacks.$stack_name.backups" "$_STACK_CONFIG_FILE" 2>/dev/null || echo "null"
}
