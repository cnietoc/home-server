#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_ROOT/docker"
STACK_CONFIG="$PROJECT_ROOT/config/stack-envs.conf"

source "$SCRIPT_DIR/common/env-loader.sh"

# Leer configuración de secretos desde archivo
load_stack_secrets_config() {
    declare -gA STACK_SECRETS

    if [[ ! -f "$STACK_CONFIG" ]]; then
        log "⚠️ No existe archivo de configuración: $STACK_CONFIG"
        return 1
    fi

    while IFS='=' read -r stack secrets || [[ -n "$stack" ]]; do
        # Ignorar líneas vacías y comentarios
        [[ -z "$stack" || "$stack" =~ ^[[:space:]]*# ]] && continue

        # Limpiar espacios
        stack=$(echo "$stack" | xargs)
        secrets=$(echo "$secrets" | xargs)

        STACK_SECRETS["$stack"]="$secrets"
    done < "$STACK_CONFIG"
}

# Obtener secretos para un stack específico
get_stack_secrets() {
    local stack_name="$1"
    echo "${STACK_SECRETS[$stack_name]:-}"
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
# Generado: $(date)
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

    # 3. Cargar secretos necesarios para este stack
    local secrets_config=$(get_stack_secrets "$stack_name")
    if [[ -n "$secrets_config" ]]; then
        echo "# === Secretos necesarios ===" >> "$temp_file"
        IFS=',' read -ra secrets_array <<< "$secrets_config"
        for secret_type in "${secrets_array[@]}"; do
            secret_type=$(echo "$secret_type" | xargs)
            local secret_file="$private_dir/$secret_type.env"
            if [[ -f "$secret_file" ]]; then
                echo "# Secretos: $secret_type" >> "$temp_file"
                cat "$secret_file" >> "$temp_file"
                echo "" >> "$temp_file"
            else
                log "⚠️ Archivo de secretos no encontrado: $secret_type.env"
            fi
        done
    fi

    # Crear directorio si no existe y mover archivo
    mkdir -p "$(dirname "$output_file")"
    mv "$temp_file" "$output_file"
    log "✅ Generado: docker/$stack_name/.env (secretos: ${secrets_config:-ninguno})"
}

# Listar configuración actual
list_stack_config() {
    log "Configuración actual de secretos por stack:"
    echo ""
    printf "%-15s | %s\n" "STACK" "SECRETOS"
    printf "%-15s-|-%s\n" "---------------" "------------------------"

    for stack in "${!STACK_SECRETS[@]}"; do
        local secrets="${STACK_SECRETS[$stack]}"
        printf "%-15s | %s\n" "$stack" "${secrets:-ninguno}"
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
    # Cargar configuración de secretos
    if ! load_stack_secrets_config; then
        log "❌ Error cargando configuración de secretos"
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
