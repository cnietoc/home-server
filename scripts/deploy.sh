#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_ROOT/docker"
CONFIG_DIR="$PROJECT_ROOT/config"
DEPLOYMENT_STATE="$PROJECT_ROOT/.deployment-state"

source "$SCRIPT_DIR/common/env-loader.sh"

# Inicializar infraestructura necesaria
initialize_infrastructure() {
    local verbose="$1"

    [[ "$verbose" == "true" ]] && log "🔧 Inicializando infraestructura..."

    # Verificar que Docker está disponible
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker no está instalado. Ejecuta: ./scripts/install-docker.sh"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        error "Docker no está corriendo. Inicia Docker Desktop o ejecuta: sudo systemctl start docker"
        return 1
    fi

    [[ "$verbose" == "true" ]] && log "✅ Docker está disponible"

    # Crear redes Docker necesarias
    if ! "$SCRIPT_DIR/setup-networks.sh" >/dev/null 2>&1; then
        error "Error inicializando redes Docker"
        return 1
    fi

    [[ "$verbose" == "true" ]] && log "✅ Redes Docker inicializadas"
}

# Calcular hash de toda la carpeta del stack
get_stack_config_hash() {
    local stack_name="$1"
    local stack_dir="$DOCKER_DIR/$stack_name"

    if [[ -d "$stack_dir" ]]; then
        # Calcular hash de todos los archivos en la carpeta del stack
        find "$stack_dir" -type f -print0 2>/dev/null | sort -z | xargs -0 cat 2>/dev/null | shasum -a 256 | cut -d' ' -f1
    else
        echo "no_stack"
    fi
}

# Verificar si han cambiado los archivos de configuración para un stack específico
stack_config_has_changed() {
    local stack_name="$1"
    local current_hash=$(get_stack_config_hash "$stack_name")
    local stored_hash=""

    if [[ -f "$DEPLOYMENT_STATE" ]]; then
        stored_hash=$(grep "^${stack_name}_hash=" "$DEPLOYMENT_STATE" 2>/dev/null | cut -d'=' -f2 || echo "")
    fi

    [[ "$current_hash" != "$stored_hash" ]]
}

# Obtener todos los stacks que han cambiado
get_changed_stacks() {
    local changed_stacks=()

    for stack_dir in "$DOCKER_DIR"/*/; do
        if [[ -d "$stack_dir" && -f "$stack_dir/docker-compose.yml" ]]; then
            local stack_name="$(basename "$stack_dir")"
            if stack_config_has_changed "$stack_name"; then
                changed_stacks+=("$stack_name")
            fi
        fi
    done

    printf "%s " "${changed_stacks[@]}"
}

# Guardar estado del despliegue para un stack específico
save_stack_deployment_state() {
    local stack_name="$1"
    local config_hash=$(get_stack_config_hash "$stack_name")
    local timestamp=$(date +%s)

    # Crear archivo de estado si no existe
    touch "$DEPLOYMENT_STATE"

    # Eliminar entrada anterior del stack si existe
    grep -v "^${stack_name}_hash=" "$DEPLOYMENT_STATE" > "${DEPLOYMENT_STATE}.tmp" 2>/dev/null || true

    # Añadir nueva entrada
    {
        cat "${DEPLOYMENT_STATE}.tmp" 2>/dev/null || true
        echo "${stack_name}_hash=$config_hash"
        echo "${stack_name}_last_deployment=$timestamp"
        echo "${stack_name}_last_deployment_date=$(date)"
    } > "$DEPLOYMENT_STATE"

    rm -f "${DEPLOYMENT_STATE}.tmp"
}

# Guardar estado de múltiples stacks
save_deployment_state() {
    local stacks=("$@")

    for stack in "${stacks[@]}"; do
        save_stack_deployment_state "$stack"
    done

    # Actualizar timestamp global
    local timestamp=$(date +%s)
    grep -v "^last_deployment" "$DEPLOYMENT_STATE" > "${DEPLOYMENT_STATE}.tmp" 2>/dev/null || true
    {
        cat "${DEPLOYMENT_STATE}.tmp" 2>/dev/null || true
        echo "last_deployment=$timestamp"
        echo "last_deployment_date=$(date)"
    } > "$DEPLOYMENT_STATE"
    rm -f "${DEPLOYMENT_STATE}.tmp"
}

# Regenerar .env files para stacks específicos
regenerate_stack_env_files() {
    local stacks=("$@")
    local regenerated=()

    for stack in "${stacks[@]}"; do
        if ! "$SCRIPT_DIR/generate-docker-envs.sh" "$stack" >/dev/null 2>&1; then
            error "Error regenerando archivo .env para stack: $stack"
            return 1
        fi
        regenerated+=("$stack")
    done

    if [[ ${#regenerated[@]} -gt 0 ]]; then
        log "🔄 Archivos .env regenerados para: ${regenerated[*]}"
        return 0
    else
        return 1
    fi
}

# Verificar si han cambiado archivos de configuración (excluyendo .env generados)
config_sources_have_changed() {
    local config_files=(
        "$CONFIG_DIR/templates"
        "$CONFIG_DIR/stack-envs.conf"
    )

    # Incluir archivos de configuración privada si existe el enlace
    if [[ -L "$CONFIG_DIR/private" ]]; then
        config_files+=("$CONFIG_DIR/private")
    fi

    local current_hash
    current_hash=$(find "${config_files[@]}" -type f 2>/dev/null | sort | xargs cat 2>/dev/null | shasum -a 256 | cut -d' ' -f1)

    local stored_hash=""
    if [[ -f "$DEPLOYMENT_STATE" ]]; then
        stored_hash=$(grep "^config_sources_hash=" "$DEPLOYMENT_STATE" 2>/dev/null | cut -d'=' -f2 || echo "")
    fi

    [[ "$current_hash" != "$stored_hash" ]]
}

# Guardar hash de archivos fuente de configuración
save_config_sources_hash() {
    local config_files=(
        "$CONFIG_DIR/templates"
        "$CONFIG_DIR/stack-envs.conf"
    )

    if [[ -L "$CONFIG_DIR/private" ]]; then
        config_files+=("$CONFIG_DIR/private")
    fi

    local current_hash
    current_hash=$(find "${config_files[@]}" -type f 2>/dev/null | sort | xargs cat 2>/dev/null | shasum -a 256 | cut -d' ' -f1)

    # Crear archivo de estado si no existe
    touch "$DEPLOYMENT_STATE"

    # Actualizar hash de fuentes de configuración
    grep -v "^config_sources_hash=" "$DEPLOYMENT_STATE" > "${DEPLOYMENT_STATE}.tmp" 2>/dev/null || true
    {
        cat "${DEPLOYMENT_STATE}.tmp" 2>/dev/null || true
        echo "config_sources_hash=$current_hash"
    } > "$DEPLOYMENT_STATE"
    rm -f "${DEPLOYMENT_STATE}.tmp"
}

# Regenerar archivos .env basándose en cambios en archivos fuente
regenerate_env_files() {
    local force="$1"
    local verbose="$2"

    if [[ "$force" == "true" ]] || config_sources_have_changed; then
        if [[ "$force" == "true" ]]; then
            [[ "$verbose" == "true" ]] && log "🔄 Regenerando todos los archivos .env (forzado)..."
        else
            [[ "$verbose" == "true" ]] && log "🔄 Regenerando archivos .env (detectados cambios en configuración)..."
        fi

        if ! "$SCRIPT_DIR/generate-docker-envs.sh" >/dev/null 2>&1; then
            error "Error regenerando archivos .env"
            return 1
        fi

        # Guardar nuevo hash de fuentes de configuración
        save_config_sources_hash

        [[ "$verbose" == "false" ]] && log "✅ Archivos .env regenerados"
        return 0
    else
        [[ "$verbose" == "true" ]] && log "⏭️ Archivos de configuración no han cambiado, .env files no requieren regeneración"
        return 1
    fi
}

# Obtener todos los stacks disponibles
get_available_stacks() {
    local all_stacks=()

    for stack_dir in "$DOCKER_DIR"/*/; do
        if [[ -d "$stack_dir" && -f "$stack_dir/docker-compose.yml" ]]; then
            all_stacks+=("$(basename "$stack_dir")")
        fi
    done

    printf "%s " "${all_stacks[@]}"
}

# Verificar estado de un stack después del despliegue
verify_stack_health() {
    local stack_name="$1"
    local stack_dir="$DOCKER_DIR/$stack_name"

    cd "$stack_dir"

    # Esperar un momento para que los contenedores se estabilicen
    sleep 3

    # Verificar que todos los contenedores están corriendo
    local running_containers=$(docker-compose ps -q 2>/dev/null | wc -l)
    local expected_containers=$(docker-compose config --services 2>/dev/null | wc -l)

    if [[ $running_containers -eq $expected_containers && $running_containers -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Obtener información del último despliegue
get_deployment_info() {
    if [[ ! -f "$DEPLOYMENT_STATE" ]]; then
        echo "❓ Nunca se ha desplegado"
        return
    fi

    local last_deployment=$(grep "^last_deployment=" "$DEPLOYMENT_STATE" 2>/dev/null | cut -d'=' -f2 || echo "0")
    local last_date=$(grep "^last_deployment_date=" "$DEPLOYMENT_STATE" 2>/dev/null | cut -d'=' -f2- || echo "Desconocido")

    if [[ $last_deployment -gt 0 ]]; then
        local hours_ago=$(( ($(date +%s) - last_deployment) / 3600 ))
        echo "📅 Último despliegue: hace ${hours_ago}h ($last_date)"
    fi
}

show_help() {
    cat << EOF
Uso: $0 [opciones] [stack1] [stack2] ...

DESCRIPCIÓN:
  Script principal de despliegue del home server. Inicializa la infraestructura,
  detecta cambios en configuración, regenera .env files automáticamente y
  despliega los stacks especificados.

OPCIONES:
  -r, --recreate       Recrear contenedores completamente
  -f, --force          Forzar despliegue sin detección de cambios
  --force-envs         Forzar regeneración de .env files
  --skip-infrastructure Saltar inicialización de infraestructura
  -l, --list           Listar stacks disponibles
  -v, --verbose        Mostrar información detallada
  -h, --help           Mostrar esta ayuda

EJEMPLOS:
  $0                           # Despliegue completo (detecta cambios automáticamente)
  $0 network                   # Desplegar solo stack network
  $0 --recreate helloworld     # Recrear contenedores de helloworld
  $0 network helloworld        # Desplegar múltiples stacks
  $0 --list                    # Ver stacks disponibles
  $0 --force                   # Forzar despliegue completo sin detección

CARACTERÍSTICAS:
  ✅ Inicializa redes Docker automáticamente
  ✅ Detecta cambios en configuración
  ✅ Regenera .env files solo si es necesario
  ✅ Despliega stacks independientemente
  ✅ Verificación de estado post-despliegue
EOF
}

list_stacks() {
    log "Stacks disponibles:"
    for stack_dir in "$DOCKER_DIR"/*/; do
        if [[ -d "$stack_dir" && -f "$stack_dir/docker-compose.yml" ]]; then
            local stack_name="$(basename "$stack_dir")"
            local status="⏹️"

            # Verificar si está corriendo (básico)
            if docker-compose -f "$stack_dir/docker-compose.yml" ps -q 2>/dev/null | grep -q .; then
                status="🟢"
            fi

            echo "  $status $stack_name"
        fi
    done
}

redeploy_stack() {
    local stack_name="$1"
    local force_recreate="${2:-false}"
    local stack_dir="$DOCKER_DIR/$stack_name"

    if [[ ! -d "$stack_dir" ]]; then
        log "❌ Stack no encontrado: $stack_name"
        return 1
    fi

    if [[ ! -f "$stack_dir/docker-compose.yml" ]]; then
        log "❌ No existe docker-compose.yml en: $stack_name"
        return 1
    fi

    log "🔄 Redespliegando stack: $stack_name"

    cd "$stack_dir"

    if [[ "$force_recreate" == "true" ]]; then
        log "♻️ Recreando contenedores completamente..."
        docker-compose up -d --force-recreate
    else
        log "🔃 Reiniciando con nueva configuración..."
        # Parar y volver a levantar para tomar nuevas variables
        docker-compose down
        docker-compose up -d
    fi

    # Verificar estado
    sleep 2
    if docker-compose ps -q | grep -q .; then
        log "✅ Stack $stack_name desplegado correctamente"
        docker-compose ps
    else
        log "⚠️ Posible problema con stack $stack_name"
        docker-compose logs --tail=20
        return 1
    fi
}

# Función principal
main() {
    local force_recreate=false
    local force_deploy=false
    local force_envs=false
    local skip_infrastructure=false
    local verbose=false
    local stacks_to_deploy=()

    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--recreate)
                force_recreate=true
                shift
                ;;
            -f|--force)
                force_deploy=true
                shift
                ;;
            --force-envs)
                force_envs=true
                shift
                ;;
            --skip-infrastructure)
                skip_infrastructure=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -l|--list)
                list_stacks
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo "❌ Opción desconocida: $1"
                show_help
                exit 1
                ;;
            *)
                stacks_to_deploy+=("$1")
                shift
                ;;
        esac
    done

    # Mostrar información del estado actual
    echo "🚀 Home Server - Script de Despliegue"
    echo "====================================="
    get_deployment_info
    echo ""

    # Inicializar infraestructura si no se omite
    if [[ "$skip_infrastructure" == "false" ]]; then
        if ! initialize_infrastructure "$verbose"; then
            exit 1
        fi
        [[ "$verbose" == "false" ]] && log "✅ Infraestructura inicializada"
    fi

    # Regenerar .env files si es necesario
    local envs_regenerated=false
    if regenerate_env_files "$force_envs" "$verbose"; then
        envs_regenerated=true
        [[ "$verbose" == "false" ]] && log "✅ Archivos .env regenerados"
    fi

    # Determinar qué stacks desplegar
    if [[ ${#stacks_to_deploy[@]} -eq 0 ]]; then
        # Si no se especificaron stacks específicos
        if [[ "$force_deploy" == "true" ]]; then
            # Forzar despliegue de todos los stacks
            log "📦 Desplegando todos los stacks (forzado)..."
            read -a stacks_to_deploy <<< "$(get_available_stacks)"
        else
            # Detectar automáticamente qué stacks han cambiado
            local changed_stacks
            read -a changed_stacks <<< "$(get_changed_stacks)"

            if [[ ${#changed_stacks[@]} -gt 0 ]]; then
                log "📦 Desplegando stacks con cambios detectados: ${changed_stacks[*]}"
                stacks_to_deploy=("${changed_stacks[@]}")
            else
                log "⏭️ No hay cambios detectados en ningún stack."
                log "💡 Usa --force para desplegar todos de todos modos."
                log "💡 O especifica stacks específicos: $0 network helloworld"
                echo ""
                list_stacks
                exit 0
            fi
        fi
    else
        # Se especificaron stacks específicos, verificar si han cambiado
        local specified_changed=()
        local specified_unchanged=()

        for stack in "${stacks_to_deploy[@]}"; do
            if stack_config_has_changed "$stack"; then
                specified_changed+=("$stack")
            else
                specified_unchanged+=("$stack")
            fi
        done

        if [[ ${#specified_changed[@]} -gt 0 ]]; then
            log "📦 De los stacks especificados, tienen cambios: ${specified_changed[*]}"
        fi

        if [[ ${#specified_unchanged[@]} -gt 0 ]]; then
            if [[ "$force_deploy" == "true" ]]; then
                log "🔄 Desplegando también (forzado): ${specified_unchanged[*]}"
            else
                log "⏭️ Sin cambios (se omiten): ${specified_unchanged[*]}"
                log "💡 Usa --force para desplegar todos los especificados sin importar cambios"
                # Solo desplegar los que han cambiado
                stacks_to_deploy=("${specified_changed[@]}")
            fi
        fi

        # Si no hay stacks para desplegar después del filtro
        if [[ ${#stacks_to_deploy[@]} -eq 0 ]]; then
            log "⏭️ Ningún stack especificado requiere despliegue."
            exit 0
        fi
    fi

    # Verificar que todos los stacks especificados existen
    for stack in "${stacks_to_deploy[@]}"; do
        if [[ ! -d "$DOCKER_DIR/$stack" ]]; then
            error "Stack no encontrado: $stack"
            log "💡 Stacks disponibles:"
            list_stacks
            exit 1
        fi
    done

    # Preguntar confirmación si se va a recrear
    if [[ "$force_recreate" == "true" ]]; then
        echo ""
        warn "⚠️ Se van a RECREAR completamente los contenedores de: ${stacks_to_deploy[*]}"
        warn "Esto puede tardar más tiempo y perder datos temporales."
        read -p "¿Continuar? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "❌ Operación cancelada"
            exit 0
        fi
    fi

    # Desplegar stacks en orden
    echo ""
    log "🎯 Desplegando stacks: ${stacks_to_deploy[*]}"
    echo ""

    local success=0
    local total=${#stacks_to_deploy[@]}
    local failed_stacks=()

    for stack in "${stacks_to_deploy[@]}"; do
        if redeploy_stack "$stack" "$force_recreate"; then
            if verify_stack_health "$stack"; then
                log "✅ Stack $stack desplegado y funcionando correctamente"
                ((success++))
            else
                warn "⚠️ Stack $stack desplegado pero con posibles problemas"
                failed_stacks+=("$stack (problemas de salud)")
            fi
        else
            error "❌ Error desplegando stack $stack"
            failed_stacks+=("$stack (error de despliegue)")
        fi
        echo ""
    done

    # Guardar estado del despliegue si fue exitoso
    if [[ $success -eq $total ]]; then
        save_deployment_state "${stacks_to_deploy[@]}"
    fi

    # Resumen final
    echo "📊 RESUMEN DEL DESPLIEGUE"
    echo "=========================="
    log "✅ Exitosos: $success/$total stacks"

    if [[ ${#failed_stacks[@]} -gt 0 ]]; then
        log "❌ Con problemas: ${failed_stacks[*]}"
        echo ""
        log "💡 Para diagnosticar problemas:"
        for failed in "${failed_stacks[@]}"; do
            local stack_name="${failed%% *}"
            log "   docker-compose -f docker/$stack_name/docker-compose.yml logs"
        done
    fi

    echo ""
    if [[ $success -eq $total ]]; then
        log "🎉 Despliegue completado exitosamente"

        # Mostrar URLs de acceso si todo está bien
        if load_common_config 2>/dev/null; then
            echo ""
            log "🌐 Servicios accesibles:"
            for stack in "${stacks_to_deploy[@]}"; do
                case $stack in
                    network)
                        log "   🔀 Traefik Dashboard: https://traefik.${BASE_DOMAIN:-tu-dominio.com}"
                        ;;
                    helloworld)
                        log "   👋 Hello World: https://hello.${BASE_DOMAIN:-tu-dominio.com}"
                        ;;
                esac
            done
        fi
    else
        log "⚠️ Despliegue completado con errores"
        exit 1
    fi
}

main "$@"
