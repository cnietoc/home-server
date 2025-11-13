#!/usr/bin/env bash
set -uo pipefail

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
    return 0
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

    # Debug información (temporal)
    if [[ "${DEPLOY_DEBUG:-}" == "true" ]]; then
        log "🔍 DEBUG Stack $stack_name - Hash actual: ${current_hash:0:16}..."
        log "🔍 DEBUG Stack $stack_name - Hash almacenado: ${stored_hash:0:16}..."
        if [[ "$current_hash" != "$stored_hash" ]]; then
            log "🔍 DEBUG Stack $stack_name - ✅ CAMBIO DETECTADO"
        else
            log "🔍 DEBUG Stack $stack_name - ⏭️ Sin cambios"
        fi
    fi

    [[ "$current_hash" != "$stored_hash" ]]
}

# Obtener todos los stacks que han cambiado con platform primero
get_changed_stacks() {
    local changed_stacks=()

    # Verificar platform primero
    if [[ -d "$DOCKER_DIR/platform" && -f "$DOCKER_DIR/platform/docker-compose.yml" ]]; then
        if stack_config_has_changed "platform"; then
            changed_stacks+=("platform")
        fi
    fi

    # Verificar resto de stacks usando stack-info.sh
    local available_stacks
    available_stacks=$("$SCRIPT_DIR/stack-info.sh" get_available_stacks 2>/dev/null || echo "")

    if [[ -n "$available_stacks" ]]; then
        while IFS= read -r stack_name; do
            [[ -z "$stack_name" ]] && continue
            if [[ "$stack_name" != "platform" ]] && [[ -d "$DOCKER_DIR/$stack_name" ]] && stack_config_has_changed "$stack_name"; then
                changed_stacks+=("$stack_name")
            fi
        done <<< "$available_stacks"
    fi

    printf "%s " "${changed_stacks[@]}"
}

# Guardar estado del despliegue para un stack específico
save_stack_deployment_state() {
    local stack_name="$1"
    local config_hash=$(get_stack_config_hash "$stack_name")
    local timestamp=$(date +%s)

    # Crear archivo de estado si no existe
    touch "$DEPLOYMENT_STATE"

    # Eliminar TODAS las entradas anteriores del stack (las 3 líneas)
    grep -v "^${stack_name}_hash=" "$DEPLOYMENT_STATE" | \
    grep -v "^${stack_name}_last_deployment=" | \
    grep -v "^${stack_name}_last_deployment_date=" > "${DEPLOYMENT_STATE}.tmp" 2>/dev/null || true

    # Añadir nuevas entradas
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
    # Eliminar AMBAS líneas globales anteriores
    grep -v "^last_deployment=" "$DEPLOYMENT_STATE" | \
    grep -v "^last_deployment_date=" > "${DEPLOYMENT_STATE}.tmp" 2>/dev/null || true
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
        "$CONFIG_DIR/stacks.yml"
        "$SCRIPT_DIR/stack-info.sh"
    )

    # Incluir archivos de configuración privada si existe el enlace
    if [[ -L "$CONFIG_DIR/private" ]]; then
        config_files+=("$CONFIG_DIR/private")
    fi

    # Calcular hash de manera más robusta
    local current_hash=""
    local temp_content=""

    for config_path in "${config_files[@]}"; do
        if [[ -e "$config_path" ]]; then
            # Usar find con -follow para seguir enlaces simbólicos
            temp_content+=$(find "$config_path" -follow -type f 2>/dev/null | sort | while read -r file; do
                echo "FILE:$file"
                cat "$file" 2>/dev/null || true
            done)
        fi
    done

    current_hash=$(echo "$temp_content" | shasum -a 256 | cut -d' ' -f1)

    local stored_hash=""
    if [[ -f "$DEPLOYMENT_STATE" ]]; then
        stored_hash=$(grep "^config_sources_hash=" "$DEPLOYMENT_STATE" 2>/dev/null | cut -d'=' -f2 || echo "")
    fi

    # Debug información (temporal)
    if [[ "${DEPLOY_DEBUG:-}" == "true" ]]; then
        log "🔍 DEBUG: Config hash actual: $current_hash"
        log "🔍 DEBUG: Config hash almacenado: $stored_hash"
        log "🔍 DEBUG: Archivos incluidos: ${config_files[*]}"
    fi

    [[ "$current_hash" != "$stored_hash" ]]
}

# Guardar hash de archivos fuente de configuración
save_config_sources_hash() {
    local config_files=(
        "$CONFIG_DIR/templates"
        "$CONFIG_DIR/stacks.yml"
        "$SCRIPT_DIR/stack-info.sh"
    )

    if [[ -L "$CONFIG_DIR/private" ]]; then
        config_files+=("$CONFIG_DIR/private")
    fi

    # Usar la misma lógica que config_sources_have_changed
    local current_hash=""
    local temp_content=""

    for config_path in "${config_files[@]}"; do
        if [[ -e "$config_path" ]]; then
            temp_content+=$(find "$config_path" -follow -type f 2>/dev/null | sort | while read -r file; do
                echo "FILE:$file"
                cat "$file" 2>/dev/null || true
            done)
        fi
    done

    current_hash=$(echo "$temp_content" | shasum -a 256 | cut -d' ' -f1)

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

# Obtener todos los stacks disponibles con platform primero
get_available_stacks() {
    local all_stacks=()
    local platform_found=false

    # Primero agregar platform si existe
    if [[ -d "$DOCKER_DIR/platform" && -f "$DOCKER_DIR/platform/docker-compose.yml" ]]; then
        all_stacks+=("platform")
        platform_found=true
    fi

    # Luego agregar el resto usando stack-info.sh
    local available_stacks
    available_stacks=$("$SCRIPT_DIR/stack-info.sh" get_available_stacks 2>/dev/null || echo "")

    if [[ -n "$available_stacks" ]]; then
        while IFS= read -r stack_name; do
            [[ -z "$stack_name" ]] && continue
            if [[ "$stack_name" != "platform" ]] && [[ -d "$DOCKER_DIR/$stack_name" ]]; then
                all_stacks+=("$stack_name")
            fi
        done <<< "$available_stacks"
    fi

    printf "%s " "${all_stacks[@]}"
}

# Verificar estado de un stack después del despliegue
verify_stack_health() {
    local stack_name="$1"
    local stack_dir="$DOCKER_DIR/$stack_name"

    if ! cd "$stack_dir"; then
        return 1
    fi

    # Tiempos conservadores para cualquier stack
    local max_wait_time=180  # 1.5 minutos
    local check_interval=8
    local stabilization_wait=10  # Espera adicional para estabilización

    log "⏱️ Verificando salud del stack $stack_name (máximo ${max_wait_time}s)..."

    local expected_containers=$(docker compose config --services 2>/dev/null | wc -l)
    expected_containers=${expected_containers:-0}
    local elapsed_time=0
    local last_running_count=0

    # Espera inicial mínima
    sleep 5

    while [[ $elapsed_time -lt $max_wait_time ]]; do
        # Contar contenedores en diferentes estados
        local running_containers=$(docker compose ps -q --status running 2>/dev/null | wc -l)
        running_containers=${running_containers:-0}

        local healthy_containers=$(docker compose ps --format "table {{.State}}" 2>/dev/null | grep -c "healthy\|running" 2>/dev/null)
        healthy_containers=${healthy_containers:-0}

        local total_containers=$(docker compose ps -a -q 2>/dev/null | wc -l)
        total_containers=${total_containers:-0}

        # Mostrar progreso si hay cambios
        if [[ $running_containers -ne $last_running_count ]]; then
            log "📊 Stack $stack_name: $running_containers/$expected_containers contenedores corriendo (${elapsed_time}s)"
            last_running_count=$running_containers
        fi

        # Verificar si todos los contenedores están corriendo
        if [[ $running_containers -eq $expected_containers && $running_containers -gt 0 ]]; then
            # Espera adicional para estabilización en todos los stacks
            log "⏳ Stack $stack_name detectado como corriendo, esperando estabilización adicional..."
            sleep $stabilization_wait

            # Verificación final de estabilidad
            local final_check=$(docker compose ps -q --status running 2>/dev/null | wc -l)
            final_check=${final_check:-0}
            if [[ $final_check -eq $expected_containers ]]; then
                log "✅ Stack $stack_name completamente estabilizado"
                return 0
            fi
        fi

        # Verificar si hay contenedores con errores críticos
        local failed_containers=$(docker compose ps --format "table {{.State}}" 2>/dev/null | grep -c "exited\|dead\|restarting" 2>/dev/null)
        failed_containers=${failed_containers:-0}
        if [[ $failed_containers -gt 0 && $elapsed_time -gt 30 ]]; then
            log "⚠️ Detectados contenedores con problemas en stack $stack_name"
            docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null | grep -E "exited|dead|restarting" || true
        fi

        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
    done

    # Timeout alcanzado
    log "⏰ Timeout verificando stack $stack_name después de ${max_wait_time}s"
    log "📊 Estado final: $running_containers/$expected_containers contenedores corriendo"

    # Mostrar estado detallado en caso de problemas
    log "🔍 Estado detallado de contenedores:"
    docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null || true

    # Considerar parcialmente exitoso si al menos 80% están corriendo
    local success_threshold=$(( expected_containers * 80 / 100 ))
    if [[ $running_containers -ge $success_threshold && $running_containers -gt 0 ]]; then
        log "⚠️ Stack $stack_name parcialmente funcional ($running_containers/$expected_containers)"
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
  --reset-state        Resetear estado de detección de cambios
  --skip-infrastructure Saltar inicialización de infraestructura
  -l, --list           Listar stacks disponibles
  -v, --verbose        Mostrar información detallada
  --debug              Mostrar información de debug para troubleshooting
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

    # Usar stack-info.sh para obtener lista de stacks
    local available_stacks
    available_stacks=$("$SCRIPT_DIR/stack-info.sh" get_available_stacks 2>/dev/null || echo "")

    if [[ -n "$available_stacks" ]]; then
        while IFS= read -r stack_name; do
            [[ -z "$stack_name" ]] && continue

            if [[ -d "$DOCKER_DIR/$stack_name" ]]; then
                local status="⏹️"
                local stack_dir="$DOCKER_DIR/$stack_name"

                # Verificar si está corriendo (básico)
                if [[ -f "$stack_dir/docker-compose.yml" ]] && docker compose -f "$stack_dir/docker-compose.yml" ps -q 2>/dev/null | grep -q .; then
                    status="🟢"
                fi

                echo "  $status $stack_name"
            else
                echo "  ⚠️ $stack_name (directorio docker no encontrado)"
            fi
        done <<< "$available_stacks"
    else
        log "❌ No se pudieron obtener stacks desde stack-info.sh"
        log "   Verifica que config/stacks.yml exista y sea válido"
    fi
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

    if ! cd "$stack_dir"; then
        error "Error accediendo al directorio: $stack_dir"
        return 1
    fi

    # Ejecutar script de pre-deploy si existe (genérico para cualquier stack)
    if [[ -f "pre-deploy.sh" ]]; then
        log "🔧 Ejecutando configuración pre-deploy para stack $stack_name..."
        if ./pre-deploy.sh; then
            log "✅ Pre-deploy completado para stack $stack_name"
        else
            warn "⚠️ Error en script pre-deploy, continuando con configuración por defecto"
        fi
    fi

    # Parar contenedores actuales
    log "⏹️ Parando contenedores actuales..."
    docker compose down --remove-orphans

    # Detectar si hay servicios que requieren build (buscar Dockerfile en cualquier parte)
    local needs_build=false
    if find . -name "Dockerfile" -type f | head -1 | grep -q .; then
        needs_build=true
    fi

    # Si hay archivos que requieren build, aplicar estrategia según fuerza
    if [[ "$needs_build" == "true" ]]; then
        if [[ "$force_recreate" == "true" ]]; then
            log "🔨 Rebuilding imagen(es) desde cero (sin caché)..."
            docker compose build --no-cache
        else
            log "🔨 Rebuilding imagen(es) (con caché)..."
            docker compose build
        fi
    fi

    if [[ "$force_recreate" == "true" ]]; then
        log "♻️ Recreando contenedores completamente..."
        docker compose up -d --force-recreate
    else
        log "🔃 Levantando con nueva configuración..."
        docker compose up -d
    fi

    # Verificar estado inicial (básico)
    log "🔍 Verificando inicio de contenedores..."
    sleep 3

    local quick_check=$(docker compose ps -q 2>/dev/null | wc -l)
    if [[ $quick_check -gt 0 ]]; then
        log "✅ Stack $stack_name iniciado (contenedores detectados)"
        log "📋 Estado inicial:"
        docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null || docker compose ps
    else
        log "❌ Ningún contenedor iniciado para stack $stack_name"
        log "🔍 Logs de error:"
        docker compose logs --tail=20
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
    local debug=false
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
            --reset-state)
                log "🔄 Reseteando estado de detección de cambios..."
                rm -f "$DEPLOYMENT_STATE"
                log "✅ Estado reseteado. Próximo despliegue detectará todos como cambios."
                exit 0
                ;;
            --skip-infrastructure)
                skip_infrastructure=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --debug)
                debug=true
                export DEPLOY_DEBUG=true
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
        local stack_result=0

        # Intentar desplegar el stack
        redeploy_stack "$stack" "$force_recreate" || stack_result=$?

        if [[ $stack_result -eq 0 ]]; then
            # Despliegue exitoso, verificar salud
            local health_result=0
            verify_stack_health "$stack" || health_result=$?

            if [[ $health_result -eq 0 ]]; then
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
            log "   docker compose -f docker/$stack_name/docker-compose.yml logs"
        done
    fi

    echo ""
    if [[ $success -eq $total ]]; then
        log "🎉 Despliegue completado exitosamente"

        # Mostrar URLs de acceso si todo está bien
        echo ""
        # Mostrar servicios usando el script centralizado
        "$SCRIPT_DIR/stack-info.sh" services "${stacks_to_deploy[@]}" 2>/dev/null || {
            log "ℹ️ No se pudo cargar información de servicios"
        }
    else
        log "⚠️ Despliegue completado con errores"
        exit 1
    fi
}

main "$@"
