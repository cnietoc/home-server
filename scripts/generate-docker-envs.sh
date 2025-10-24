#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_ROOT/docker"
STACK_CONFIG="$PROJECT_ROOT/config/stack-envs.conf"

source "$SCRIPT_DIR/common/env-loader.sh"

# Leer configuración de variables desde archivo
load_stack_config() {
    declare -gA STACK_CONFIG

    if [[ ! -f "$STACK_CONFIG" ]]; then
        log "⚠️ No existe archivo de configuración: $STACK_CONFIG"
        return 1
    fi

    while IFS='=' read -r stack config_vars || [[ -n "$stack" ]]; do
        # Ignorar líneas vacías y comentarios
        [[ -z "$stack" || "$stack" =~ ^[[:space:]]*# ]] && continue

        # Limpiar espacios
        stack=$(echo "$stack" | xargs)
        config_vars=$(echo "$config_vars" | xargs)

        STACK_CONFIG["$stack"]="$config_vars"
    done < "$STACK_CONFIG"
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

    # Header informativo
    cat > "$temp_file" << EOF
# ======================================
# Archivo generado automáticamente
# Stack: $stack_name
# NO EDITAR MANUALMENTE
# ======================================

EOF

    # 1. Cargar variables comunes desde carpeta privada
    local common_file="$private_dir/common.env"
    if [[ -f "$common_file" ]]; then
        echo "# === Variables comunes ===" >> "$temp_file"
        cat "$common_file" >> "$temp_file"
        echo "" >> "$temp_file"
    fi

    # 2. Cargar configuración específica del stack desde carpeta privada
    local stack_file="$private_dir/$stack_name.env"
    if [[ -f "$stack_file" ]]; then
        echo "# === Configuración $stack_name ===" >> "$temp_file"
        cat "$stack_file" >> "$temp_file"
        echo "" >> "$temp_file"
    fi

    # 3. Cargar configuración adicional necesaria para este stack
    local additional_config=$(get_stack_config "$stack_name")
    if [[ -n "$additional_config" ]]; then
        echo "# === Configuración adicional ===" >> "$temp_file"
        IFS=',' read -ra config_array <<< "$additional_config"
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
    log "✅ Generado: docker/$stack_name/.env (configuración: ${additional_config:-ninguna})"
}

# Listar configuración actual
list_stack_config() {
    log "Configuración actual de variables por stack:"
    echo ""
    printf "%-15s | %s\n" "STACK" "CONFIGURACIÓN"
    printf "%-15s-|-%s\n" "---------------" "------------------------"

    for stack in "${!STACK_CONFIG[@]}"; do
        local config_vars="${STACK_CONFIG[$stack]}"
        printf "%-15s | %s\n" "$stack" "${config_vars:-ninguna}"
    done | sort
}

# Generar .env para todos los stacks
generate_all_stack_envs() {
    for stack_dir in "$DOCKER_DIR"/*/; do
        if [[ -d "$stack_dir" ]]; then
            local stack_name="$(basename "$stack_dir")"
            generate_stack_env "$stack_name"
        fi
    done
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
