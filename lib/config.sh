#!/usr/bin/env bash
# ============================================
# lib/config.sh — Librería de gestión de configuración
# Proporciona funciones para generar archivos .env y validar configuración
# ============================================

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente." >&2
    exit 1
}

# --- Inicialización de variables ---
_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CONFIG_PROJECT_ROOT="$(dirname "$_CONFIG_LIB_DIR")"
_CONFIG_DIR="${_CONFIG_PROJECT_ROOT}/config"
_CONFIG_PRIVATE_DIR="${_CONFIG_DIR}/private"
_CONFIG_TEMPLATES_DIR="${_CONFIG_DIR}/templates"
_CONFIG_DOCKER_DIR="${_CONFIG_PROJECT_ROOT}/docker"

# Cargar dependencias desde lib/
source "${_CONFIG_LIB_DIR}/logs.sh"
source "${_CONFIG_LIB_DIR}/stack.sh"

# ============================================
# FUNCIONES DE VALIDACIÓN
# ============================================

# Verificar que existe el enlace simbólico a config/private
config::verify_private_link() {
    if [[ ! -L "$_CONFIG_PRIVATE_DIR" ]]; then
        logs::error "Enlace simbólico no encontrado: $_CONFIG_PRIVATE_DIR"
        logs::info "💡 Crea el enlace con: hms config link <ruta>"
        return 1
    fi

    if [[ ! -d "$_CONFIG_PRIVATE_DIR" ]]; then
        logs::error "El enlace apunta a una carpeta inexistente: $_CONFIG_PRIVATE_DIR"
        return 1
    fi

    return 0
}

# Verificar que existe un archivo de configuración
config::env_file_exists() {
    local config_type="$1"
    local env_file="${_CONFIG_PRIVATE_DIR}/${config_type}.env"

    [[ -f "$env_file" ]]
}

# Verificar que existen todos los archivos de configuración necesarios para un stack
config::verify_stack_config_files() {
    local stack="$1"
    local missing_files=()

    # Obtener archivos de configuración del stack
    local config_files
    config_files=$(stack::get_config_files "$stack")

    if [[ -z "$config_files" ]]; then
        return 0
    fi

    # Verificar cada archivo
    IFS=',' read -ra config_array <<< "$config_files"
    for config_type in "${config_array[@]}"; do
        config_type=$(echo "$config_type" | xargs)
        if ! config::env_file_exists "$config_type"; then
            missing_files+=("$config_type")
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        logs::warn "⚠️ Archivos de configuración faltantes para stack $stack:"
        for file in "${missing_files[@]}"; do
            logs::warn "   - $file.env"
        done
        return 1
    fi

    return 0
}

# ============================================
# FUNCIONES DE GENERACIÓN
# ============================================

# Generar archivo .env para un stack específico
config::generate_stack_env() {
    local stack="$1"
    local output_file="${_CONFIG_DOCKER_DIR}/${stack}/.env"
    local temp_file
    temp_file=$(mktemp)

    # Verificar enlace privado
    if ! config::verify_private_link; then
        rm -f "$temp_file"
        return 1
    fi

    # Header informativo y variables dinámicas
    cat > "$temp_file" << EOF
# ======================================
# Archivo generado automáticamente
# Stack: $stack
# NO EDITAR MANUALMENTE
# ======================================

# Variables dinámicas del stack
STACK_NAME=$stack
STACK_DATA=../../data/$stack

EOF

    # Obtener archivos de configuración del stack
    local config_files
    config_files=$(stack::get_config_files "$stack")

    if [[ -n "$config_files" ]]; then
        echo "# === Configuración del stack ===" >> "$temp_file"

        IFS=',' read -ra config_array <<< "$config_files"
        for config_type in "${config_array[@]}"; do
            config_type=$(echo "$config_type" | xargs)
            local config_file="${_CONFIG_PRIVATE_DIR}/${config_type}.env"

            if [[ -f "$config_file" ]]; then
                echo "# Configuración: $config_type" >> "$temp_file"
                cat "$config_file" >> "$temp_file"
                echo "" >> "$temp_file"
            else
                logs::warn "⚠️ Archivo de configuración no encontrado: $config_type.env"
            fi
        done
    fi

    # Crear directorio si no existe y mover archivo
    mkdir -p "$(dirname "$output_file")"
    mv "$temp_file" "$output_file"

    return 0
}

# Generar archivos .env para todos los stacks
config::generate_all_envs() {
    # Verificar enlace privado
    if ! config::verify_private_link; then
        return 1
    fi

    local success_count=0
    local fail_count=0
    local stacks
    stacks=$(stack::list)

    while IFS= read -r stack; do
        [[ -z "$stack" ]] && continue

        # Verificar que el directorio docker existe para este stack
        if [[ ! -d "${_CONFIG_DOCKER_DIR}/${stack}" ]]; then
            logs::warn "⚠️ Stack '$stack' definido en configuración pero no tiene directorio docker"
            continue
        fi

        # Generar .env
        if config::generate_stack_env "$stack"; then
            local config_files
            config_files=$(stack::get_config_files "$stack")
            logs::info "✅ $stack (configuración: ${config_files:-ninguna})"
            success_count=$((success_count + 1))
        else
            logs::error "❌ Error generando .env para stack: $stack"
            fail_count=$((fail_count + 1))
        fi
    done <<< "$stacks"
    logs::info "📊 Generados: $success_count stacks"

    if [[ $fail_count -gt 0 ]]; then
        logs::warn "⚠️ Errores: $fail_count stacks"
        return 1
    fi

    return 0
}

# Generar archivos .env para stacks específicos
config::generate_multiple_envs() {
    local stacks=("$@")

    if [[ ${#stacks[@]} -eq 0 ]]; then
        config::generate_all_envs
        return $?
    fi

    # Verificar enlace privado
    if ! config::verify_private_link; then
        return 1
    fi

    local success_count=0
    local fail_count=0

    for stack in "${stacks[@]}"; do
        # Verificar que el stack existe
        if ! stack::exists "$stack"; then
            logs::error "❌ Stack no encontrado: $stack"
            fail_count=$((fail_count + 1))
            continue
        fi

        # Verificar que el directorio docker existe
        if [[ ! -d "${_CONFIG_DOCKER_DIR}/${stack}" ]]; then
            logs::warn "⚠️ Stack '$stack' no tiene directorio docker"
            fail_count=$((fail_count + 1))
            continue
        fi

        # Generar .env
        if config::generate_stack_env "$stack"; then
            local config_files
            config_files=$(stack::get_config_files "$stack")
            logs::info "✅ $stack (configuración: ${config_files:-ninguna})"
            success_count=$((success_count + 1))
        else
            logs::error "❌ Error generando .env para stack: $stack"
            fail_count=$((fail_count + 1))
        fi
    done
    logs::info "📊 Generados: $success_count stacks"

    if [[ $fail_count -gt 0 ]]; then
        logs::warn "⚠️ Errores: $fail_count stacks"
        return 1
    fi

    return 0
}

