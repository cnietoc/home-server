#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_ROOT/docker"

source "$SCRIPT_DIR/common/env-loader.sh"

# Obtener lista de stacks disponibles
get_available_stacks() {
    "$SCRIPT_DIR/stack-info.sh" get_available_stacks 2>/dev/null || echo ""
}

# Obtener archivos de configuración de un stack
get_stack_config_files() {
    local stack_name="$1"
    "$SCRIPT_DIR/stack-info.sh" get_stack_config_files "$stack_name" 2>/dev/null || echo ""
}

# Obtener descripción de un stack
get_stack_description() {
    local stack_name="$1"
    "$SCRIPT_DIR/stack-info.sh" get_stack_description "$stack_name" 2>/dev/null || echo ""
}

# Verificar si un stack existe
stack_exists() {
    local stack_name="$1"
    "$SCRIPT_DIR/stack-info.sh" stack_exists "$stack_name" 2>/dev/null
}

# Cargar configuración de stacks usando stack-info.sh
load_stack_config() {
    declare -gA STACK_CONFIG

    # Verificar que stack-info.sh esté disponible y funcional
    if ! "$SCRIPT_DIR/stack-info.sh" init_stack_info >/dev/null 2>&1; then
        log "❌ Error: No se pudo inicializar stack-info"
        return 1
    fi

    # Obtener lista de stacks
    local stacks
    stacks=$(get_available_stacks) || {
        log "❌ Error obteniendo lista de stacks"
        return 1
    }

    while IFS= read -r stack; do
        [[ -z "$stack" ]] && continue

        # Obtener archivos de configuración para este stack
        local config_files
        config_files=$(get_stack_config_files "$stack")

        STACK_CONFIG["$stack"]="$config_files"

    done <<< "$stacks"
}

# Obtener configuración para un stack específico
get_stack_config() {
    local stack_name="$1"
    echo "${STACK_CONFIG[$stack_name]:-}"
}

# Generar .env combinado para un stack específico
generate_stack_env() {
    local stack_name="$1"
    local output_file="$DOCKER_DIR/$stack_name/.env"
    local temp_file=$(mktemp)

    # Obtener ruta de carpeta privada
    local private_dir
    if ! private_dir="$(get_private_dir)"; then
        rm -f "$temp_file"
        return 1
    fi

    # Header informativo y variables dinámicas
    cat > "$temp_file" << EOF
# ======================================
# Archivo generado automáticamente
# Stack: $stack_name
# NO EDITAR MANUALMENTE
# ======================================

# Variables dinámicas del stack
STACK_NAME=$stack_name
STACK_DATA=../../data/$stack_name

EOF

    # Cargar todos los archivos .env configurados
    local all_config=$(get_stack_config "$stack_name")
    if [[ -n "$all_config" ]]; then
        echo "# === Configuración del stack ===" >> "$temp_file"
        IFS=',' read -ra config_array <<< "$all_config"
        for config_type in "${config_array[@]}"; do
            config_type=$(echo "$config_type" | xargs)
            local config_file="$private_dir/$config_type.env"
            if [[ -f "$config_file" ]]; then
                echo "# Configuración: $config_type" >> "$temp_file"
                cat "$config_file" >> "$temp_file"
                echo "" >> "$temp_file"
            else
                log "⚠️ Archivo de configuración no encontrado: $config_type.env"
            fi
        done
    fi

    # Crear directorio si no existe y mover archivo
    mkdir -p "$(dirname "$output_file")"
    mv "$temp_file" "$output_file"
    log "✅ Generado: docker/$stack_name/.env (configuración: ${all_config:-ninguna})"
}

# Listar configuración actual
list_stack_config() {
    log "📋 Configuración de variables por stack:"
    echo ""

    printf "%-15s | %-30s | %s\n" "STACK" "ARCHIVOS CONFIGURACIÓN" "DESCRIPCIÓN"
    printf "%-15s-|-%s-|-%s\n" "---------------" "------------------------------" "------------------------"

    # Cargar configuración de stacks
    if ! load_stack_config; then
        log "❌ Error cargando configuración de stacks"
        return 1
    fi

    for stack in $(printf '%s\n' "${!STACK_CONFIG[@]}" | sort); do
        local config_vars="${STACK_CONFIG[$stack]}"

        # Obtener descripción usando stack-info wrapper
        local description
        description=$(get_stack_description "$stack")
        [[ -z "$description" ]] && description="Sin descripción"

        printf "%-15s | %-30s | %s\n" "$stack" "$config_vars" "$description"
    done
}

# Generar .env para todos los stacks
generate_all_stack_envs() {
    local private_dir
    if ! private_dir="$(get_private_dir)"; then
        return 1
    fi

    for stack_dir in "$DOCKER_DIR"/*/; do
        if [[ -d "$stack_dir" ]]; then
            local stack_name="$(basename "$stack_dir")"
            # Asegurar todos los archivos de configuración (incluyendo common)
            local all_config=$(get_stack_config "$stack_name")
            if [[ -n "$all_config" ]]; then
                IFS=',' read -ra config_array <<< "$all_config"
                for config_type in "${config_array[@]}"; do
                    config_type=$(echo "$config_type" | xargs)
                    ensure_env_file_exists "$config_type" "$private_dir"
                done
            fi
            generate_stack_env "$stack_name"
        fi
    done
}

# Generar archivo .env desde template si no existe
ensure_env_file_exists() {
    local env_name="$1"
    local private_dir="$2"
    local env_file="$private_dir/$env_name.env"
    local template_file="$PROJECT_ROOT/config/templates/$env_name.env.template"

    # Si el archivo ya existe, no hacer nada
    if [[ -f "$env_file" ]]; then
        return 0
    fi

    # Si no existe template, no podemos generarlo
    if [[ ! -f "$template_file" ]]; then
        return 1
    fi

    # Generar archivo desde template
    log "📄 Generando $env_name.env desde template..."
    cp "$template_file" "$env_file"
    log "✅ Creado: config/private/$env_name.env (edítalo para configurar)"
    return 0
}

# Función principal
main() {
    # Cargar configuración de variables
    if ! load_stack_config; then
        log "❌ Error cargando configuración de variables"
        exit 1
    fi

    case "${1:-}" in
        --list|-l)
            list_stack_config
            ;;
        --help|-h)
            echo "Uso: $0 [opciones] [stack1] [stack2] ..."
            echo ""
            echo "Opciones:"
            echo "  --list, -l     Mostrar configuración actual"
            echo "  --help, -h     Mostrar esta ayuda"
            echo ""
            echo "Si no se especifican stacks, se procesan todos."
            ;;
        *)
            if [[ $# -eq 0 ]]; then
                log "Generando .env para todos los stacks..."
                generate_all_stack_envs
            else
                for stack in "$@"; do
                    if [[ -d "$DOCKER_DIR/$stack" ]]; then
                        # Asegurar todos los archivos de configuración (incluyendo common)
                        local private_dir="$(get_private_dir)"
                        local all_config=$(get_stack_config "$stack")
                        if [[ -n "$all_config" ]]; then
                            IFS=',' read -ra config_array <<< "$all_config"
                            for config_type in "${config_array[@]}"; do
                                config_type=$(echo "$config_type" | xargs)
                                ensure_env_file_exists "$config_type" "$private_dir"
                            done
                        fi
                        generate_stack_env "$stack"
                    else
                        log "⚠️ Stack no encontrado: $stack"
                    fi
                done
            fi
            ;;
    esac

    [[ "${1:-}" != "--list" && "${1:-}" != "--help" ]] && log "✅ Generación completada"
}

main "$@"
