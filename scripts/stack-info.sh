#!/usr/bin/env bash

# Script para gestionar información de stacks y servicios
# Centraliza la configuración y URLs de todos los servicios

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STACK_CONFIG="$PROJECT_ROOT/config/stacks.yml"

source "$SCRIPT_DIR/common/env-loader.sh"



# Verificar si yq está disponible
check_yq() {
    if command -v yq >/dev/null 2>&1; then
        return 0
    else
        error "yq no está instalado. Instálalo con: sudo snap install yq (Ubuntu) o brew install yq (macOS)"
        return 1
    fi
}

# Función de inicialización para otros scripts
init_stack_info() {
    if [[ ! -f "$STACK_CONFIG" ]]; then
        error "Archivo de configuración no encontrado: $STACK_CONFIG"
        return 1
    fi

    if ! check_yq; then
        return 1
    fi

    return 0
}

# Wrapper functions para usar desde otros scripts
# ================================================

# Obtener lista de stacks disponibles
get_available_stacks() {
    if ! check_yq; then
        return 1
    fi

    yq eval '.stacks | keys | .[]' "$STACK_CONFIG"
}

# Obtener archivos de configuración de un stack específico
get_stack_config_files() {
    local stack_name="$1"

    if ! check_yq; then
        return 1
    fi

    local config_files
    config_files=$(yq eval ".stacks.$stack_name.config_files | join(\",\")" "$STACK_CONFIG")

    # Siempre incluir common como base, luego agregar los específicos del stack
    if [[ "$config_files" == "null" || -z "$config_files" || "$config_files" == "" ]]; then
        echo "common"
    else
        echo "common,$config_files"
    fi
}

# Obtener descripción de un stack específico
get_stack_description() {
    local stack_name="$1"

    if ! check_yq; then
        return 1
    fi

    local description
    description=$(yq eval ".stacks.$stack_name.description" "$STACK_CONFIG" 2>/dev/null)

    if [[ "$description" == "null" ]]; then
        echo ""
    else
        echo "$description"
    fi
}

# Obtener subdomain de un servicio específico
get_service_subdomain() {
    local stack_name="$1"
    local service_name="$2"

    if ! check_yq; then
        return 1
    fi

    local subdomain
    subdomain=$(yq eval ".stacks.$stack_name.services.$service_name.subdomain" "$STACK_CONFIG" 2>/dev/null)

    if [[ "$subdomain" == "null" ]]; then
        echo ""
    else
        echo "$subdomain"
    fi
}

# Verificar si un stack existe
stack_exists() {
    local stack_name="$1"

    if ! check_yq; then
        return 1
    fi

    local exists
    exists=$(yq eval ".stacks | has(\"$stack_name\")" "$STACK_CONFIG" 2>/dev/null)

    [[ "$exists" == "true" ]]
}

# Cargar configuración de stacks usando las funciones wrapper
load_stack_info() {
    if ! init_stack_info; then
        return 1
    fi

    # Limpiar arrays globales
    declare -gA STACK_CONFIG_MAP
    declare -gA STACK_SERVICES_MAP
    declare -gA STACK_DESCRIPTIONS

    # Obtener lista de stacks usando función wrapper
    local stacks
    stacks=$(get_available_stacks) || {
        error "Error obteniendo lista de stacks"
        return 1
    }

    while IFS= read -r stack; do
        [[ -z "$stack" ]] && continue

        # Usar funciones wrapper para obtener información
        local description config_files
        description=$(get_stack_description "$stack")
        config_files=$(get_stack_config_files "$stack")

        # Almacenar en arrays globales
        [[ -n "$description" ]] && STACK_DESCRIPTIONS["$stack"]="$description"
        [[ -n "$config_files" ]] && STACK_CONFIG_MAP["$stack"]="$config_files"

        # Servicios - obtener nombres de servicios directamente con yq
        local service_names
        service_names=$(yq eval ".stacks.$stack.services | keys | .[]" "$STACK_CONFIG" 2>/dev/null)

        local service_entries=""
        while IFS= read -r service; do
            [[ -z "$service" ]] && continue

            # Obtener subdomain y descripción del servicio usando yq directo
            local subdomain desc
            subdomain=$(yq eval ".stacks.$stack.services.$service.subdomain" "$STACK_CONFIG" 2>/dev/null)
            desc=$(yq eval ".stacks.$stack.services.$service.description" "$STACK_CONFIG" 2>/dev/null)

            # Limpiar valores null
            [[ "$subdomain" == "null" ]] && subdomain=""
            [[ "$desc" == "null" ]] && desc=""

            local service_entry="$service:$subdomain:$desc"
            if [[ -n "$service_entries" ]]; then
                service_entries="$service_entries,$service_entry"
            else
                service_entries="$service_entry"
            fi
        done <<< "$service_names"

        [[ -n "$service_entries" ]] && STACK_SERVICES_MAP["$stack"]="$service_entries"

    done <<< "$stacks"
}

# Obtener archivos de configuración para un stack
get_stack_config() {
    local stack_name="$1"
    echo "${STACK_CONFIG_MAP[$stack_name]:-}"
}

# Obtener servicios para un stack
get_stack_services() {
    local stack_name="$1"
    echo "${STACK_SERVICES_MAP[$stack_name]:-}"
}

# Construir URL completa desde subdomain
build_service_url() {
    local subdomain="$1"

    # Cargar variables comunes si están disponibles
    local base_domain="tu-dominio.com"  # fallback por defecto

    if load_common_config 2>/dev/null && [[ -n "${BASE_DOMAIN:-}" ]]; then
        base_domain="$BASE_DOMAIN"
    fi

    # Construir URL completa
    echo "https://${subdomain}.${base_domain}"
}

# Mostrar servicios de stacks específicos
show_stack_services() {
    local stacks=("$@")

    if ! load_stack_info; then
        error "No se pudo cargar la configuración de stacks"
        return 1
    fi

    log "🌐 Servicios accesibles:"

    local stack_list=($(printf '%s\n' "${stacks[@]}" | sort))
    local total_stacks=${#stack_list[@]}
    local has_services=false

    for i in "${!stack_list[@]}"; do
        local stack="${stack_list[$i]}"
        local services=$(get_stack_services "$stack")

        if [[ -n "$services" ]]; then
            has_services=true

            # Determinar si es el último stack
            local is_last_stack=$((i == total_stacks - 1))
            local stack_prefix="├── "
            local indent="│   "
            if [[ $is_last_stack -eq 1 ]]; then
                stack_prefix="└── "
                indent="    "
            fi

            # Mostrar stack
            echo "${stack_prefix}📦 $stack"

            # Procesar servicios del stack
            IFS=',' read -ra service_array <<< "$services"
            local service_count=${#service_array[@]}
            for k in "${!service_array[@]}"; do
                # Parsear servicio:subdomain:descripcion
                IFS=':' read -ra service_parts <<< "${service_array[$k]}"
                local service_subdomain="${service_parts[1]:-}"
                local service_desc="${service_parts[2]:-}"

                local is_last_service=$((k == service_count - 1))
                local service_line=""

                if [[ -n "$service_subdomain" ]]; then
                    # Servicio con subdomain - construir URL completa
                    local full_url=$(build_service_url "$service_subdomain")
                    service_line="$service_desc → $full_url"
                else
                    # Servicio sin URL (solo descripción)
                    service_line="$service_desc"
                fi

                if [[ $is_last_service -eq 1 ]]; then
                    echo "${indent}└── $service_line"
                else
                    echo "${indent}├── $service_line"
                fi
            done
        fi
    done

    if [[ "$has_services" == "false" ]]; then
        log "ℹ️ No hay servicios configurados para los stacks especificados"
    fi
}

# Listar todos los stacks y sus configuraciones
list_all_stacks() {
    if ! load_stack_info; then
        error "No se pudo cargar la configuración de stacks"
        return 1
    fi

    log "📋 Configuración de stacks disponibles:"
    echo ""

    # Obtener todos los stacks únicos
    local all_stacks=()
    for stack in "${!STACK_CONFIG_MAP[@]}"; do
        all_stacks+=("$stack")
    done
    for stack in "${!STACK_SERVICES_MAP[@]}"; do
        local found=false
        for existing in "${all_stacks[@]}"; do
            if [[ "$existing" == "$stack" ]]; then
                found=true
                break
            fi
        done
        [[ "$found" == "false" ]] && all_stacks+=("$stack")
    done
    for stack in "${!STACK_DESCRIPTIONS[@]}"; do
        local found=false
        for existing in "${all_stacks[@]}"; do
            if [[ "$existing" == "$stack" ]]; then
                found=true
                break
            fi
        done
        [[ "$found" == "false" ]] && all_stacks+=("$stack")
    done

    # Mostrar información de cada stack en formato árbol
    local stack_list=($(printf '%s\n' "${all_stacks[@]}" | sort))
    local total_stacks=${#stack_list[@]}

    for i in "${!stack_list[@]}"; do
        local stack="${stack_list[$i]}"
        local description="${STACK_DESCRIPTIONS[$stack]:-Sin descripcion}"
        local config_files="${STACK_CONFIG_MAP[$stack]:-common}"
        local services="${STACK_SERVICES_MAP[$stack]:-}"

        # Determinar si es el último stack
        local is_last_stack=$((i == total_stacks - 1))
        local stack_prefix="├── "
        local indent="│   "
        if [[ $is_last_stack -eq 1 ]]; then
            stack_prefix="└── "
            indent="    "
        fi

        # Mostrar información del stack
        echo "${stack_prefix}📦 $stack"
        echo "${indent}├── 📝 $description"

        # Mostrar archivos de configuración
        echo "${indent}├── ⚙️  Configuración:"
        IFS=',' read -ra config_array <<< "$config_files"
        local config_count=${#config_array[@]}
        for j in "${!config_array[@]}"; do
            local config_file=$(echo "${config_array[$j]}" | xargs)
            local is_last_config=$((j == config_count - 1))
            if [[ $is_last_config -eq 1 ]]; then
                echo "${indent}│   └── $config_file.env"
            else
                echo "${indent}│   ├── $config_file.env"
            fi
        done

        # Mostrar servicios
        if [[ -n "$services" ]]; then
            echo "${indent}└── 🌐 Servicios:"
            IFS=',' read -ra service_array <<< "$services"
            local service_count=${#service_array[@]}
            for k in "${!service_array[@]}"; do
                # Parsear servicio:subdomain:descripcion
                IFS=':' read -ra service_parts <<< "${service_array[$k]}"
                local service_subdomain="${service_parts[1]:-}"
                local service_desc="${service_parts[2]:-}"

                local is_last_service=$((k == service_count - 1))
                local service_line=""

                if [[ -n "$service_subdomain" ]]; then
                    # Servicio con subdomain - construir URL completa
                    local full_url=$(build_service_url "$service_subdomain")
                    service_line="$service_desc → $full_url"
                else
                    # Servicio sin URL (solo descripción)
                    service_line="$service_desc"
                fi

                if [[ $is_last_service -eq 1 ]]; then
                    echo "${indent}    └── $service_line"
                else
                    echo "${indent}    ├── $service_line"
                fi
            done
        else
            echo "${indent}└── 🌐 Servicios: ninguno"
        fi


    done
}

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $0 [comando] [opciones]

DESCRIPCIÓN:
  Script centralizado para gestionar información de stacks y servicios del home server.
  Actúa como wrapper de yq para toda la configuración YAML.

COMANDOS PRINCIPALES:
  services [stack1] [stack2] ...  - Mostrar servicios de stacks específicos
  list                           - Listar todos los stacks y configuración
  config [stack]                 - Mostrar archivos de configuración de un stack
  help                          - Mostrar esta ayuda

COMANDOS WRAPPER (para otros scripts):
  get_available_stacks           - Obtener lista de todos los stacks
  get_stack_config_files [stack] - Obtener archivos .env de un stack (incluye common)
  get_stack_description [stack]  - Obtener descripción de un stack
  get_service_subdomain [stack] [service] - Obtener subdomain de un servicio
  stack_exists [stack]           - Verificar si un stack existe
  init_stack_info               - Inicializar y verificar dependencias

EJEMPLOS:
  $0 services platform           # Servicios del stack platform
  $0 list                        # Ver toda la configuración
  $0 config platform             # Ver config del stack platform

  # Uso desde otros scripts:
  $0 get_stack_config_files platform  # Retorna: common,cloudflare,auth,watchtower
  $0 stack_exists platform && echo "existe"

ARCHIVO DE CONFIGURACIÓN:
  $STACK_CONFIG

FORMATO DEL ARCHIVO (YAML):
  stacks:
    stack_name:
      description: "Descripción del stack"
      config_files:
        - config1       # Se combina con common automáticamente
        - config2
      services:
        servicio:
          subdomain: mi-servicio
          description: "🔗 Descripción del servicio"
          protected: true/false

NOTAS:
  - common.env siempre se incluye automáticamente en todos los stacks
  - subdomain se combina con BASE_DOMAIN para formar https://subdomain.BASE_DOMAIN
  - Este script es el único punto de acceso al archivo YAML desde otros scripts

DEPENDENCIAS:
  - yq (requerido) - instalar con: sudo snap install yq (Ubuntu) o brew install yq (macOS)
EOF
}

# Mostrar configuración de un stack específico
show_stack_config() {
    local stack_name="$1"

    if ! load_stack_info; then
        error "No se pudo cargar la configuración de stacks"
        return 1
    fi

    local config_files=$(get_stack_config "$stack_name")
    local services=$(get_stack_services "$stack_name")

    log "📋 Configuración del stack: $stack_name"
    echo ""

    log "📁 Archivos de configuración:"
    if [[ -n "$config_files" ]]; then
        IFS=',' read -ra config_array <<< "$config_files"
        for config_file in "${config_array[@]}"; do
            config_file=$(echo "$config_file" | xargs)
            log "   - $config_file.env"
        done
    else
        log "   - common.env (por defecto)"
    fi

    echo ""
    log "🌐 Servicios:"
    if [[ -n "$services" ]]; then
        show_stack_services "$stack_name"
    else
        log "   - Ningún servicio configurado"
    fi
}


# Función principal
main() {
    case "${1:-help}" in
        "services")
            shift
            if [[ $# -eq 0 ]]; then
                error "Especifica al menos un stack"
                echo "Uso: $0 services [stack1] [stack2] ..."
                exit 1
            fi
            show_stack_services "$@"
            ;;
        "list")
            list_all_stacks
            ;;
        "config")
            if [[ -z "${2:-}" ]]; then
                error "Especifica un stack"
                echo "Uso: $0 config [stack_name]"
                exit 1
            fi
            show_stack_config "$2"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        # Comandos wrapper para otros scripts
        "get_available_stacks")
            get_available_stacks
            ;;
        "get_stack_config_files")
            if [[ -z "${2:-}" ]]; then
                exit 1
            fi
            get_stack_config_files "$2"
            ;;
        "get_stack_description")
            if [[ -z "${2:-}" ]]; then
                exit 1
            fi
            get_stack_description "$2"
            ;;
        "get_service_subdomain")
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                exit 1
            fi
            get_service_subdomain "$2" "$3"
            ;;
        "stack_exists")
            if [[ -z "${2:-}" ]]; then
                exit 1
            fi
            stack_exists "$2"
            ;;
        "init_stack_info")
            init_stack_info
            ;;
        *)
            echo "❌ Comando desconocido: ${1:-}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
