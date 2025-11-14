#!/usr/bin/env bash
# ============================================
# lib/docker.sh — Librería de gestión de Docker
# Proporciona funciones para verificar Docker, infraestructura y operaciones con compose
# ============================================

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente." >&2
    exit 1
}

# --- Inicialización de variables ---
_DOCKER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DOCKER_PROJECT_ROOT="$(dirname "$_DOCKER_LIB_DIR")"
_DOCKER_DIR="${_DOCKER_PROJECT_ROOT}/docker"

# Cargar dependencias desde lib/
source "${_DOCKER_LIB_DIR}/logs.sh"

# ============================================
# FUNCIONES DE VERIFICACIÓN
# ============================================

# Verificar que Docker está instalado
docker::is_installed() {
    command -v docker >/dev/null 2>&1
}

# Verificar que Docker está corriendo
docker::is_running() {
    docker info >/dev/null 2>&1
}

# Verificar Docker completamente (instalado y corriendo)
docker::verify() {
    if ! docker::is_installed; then
        logs::error "Docker no está instalado"
        logs::info "💡 Ejecuta: ./commands/setup/docker"
        return 1
    fi

    if ! docker::is_running; then
        logs::error "Docker no está corriendo"
        logs::info "💡 Inicia Docker Desktop o ejecuta: sudo systemctl start docker"
        return 1
    fi

    return 0
}

# ============================================
# FUNCIONES DE INFRAESTRUCTURA
# ============================================

# Inicializar redes Docker
docker::init_networks() {
    if ! "${_DOCKER_LIB_DIR}/../commands/setup/networks" >/dev/null 2>&1; then
        logs::error "Error inicializando redes Docker"
        return 1
    fi

    return 0
}

# Inicializar toda la infraestructura necesaria
docker::init_infrastructure() {
    # Verificar Docker
    if ! docker::verify; then
        return 1
    fi

    # Inicializar redes
    if ! docker::init_networks; then
        return 1
    fi

    return 0
}

# ============================================
# FUNCIONES DE COMPOSE - INFORMACIÓN
# ============================================

# Verificar si un stack tiene docker-compose.yml
docker::stack::has_compose() {
    local stack="$1"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    [[ -f "${stack_dir}/docker-compose.yml" ]]
}

# Verificar si un stack existe (tiene directorio)
docker::stack::exists() {
    local stack="$1"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    [[ -d "$stack_dir" ]]
}

# Obtener número de servicios esperados en un stack
docker::stack::get_service_count() {
    local stack="$1"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if ! docker::stack::has_compose "$stack"; then
        echo "0"
        return 0
    fi

    cd "$stack_dir" || return 1
    docker compose config --services 2>/dev/null | wc -l | tr -d ' '
}

# Verificar si un stack tiene servicios que necesitan build
docker::stack::needs_build() {
    local stack="$1"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if ! docker::stack::exists "$stack"; then
        return 1
    fi

    # Buscar Dockerfiles en el directorio del stack
    find "$stack_dir" -name "Dockerfile" -type f 2>/dev/null | head -1 | grep -q .
}

# ============================================
# FUNCIONES DE COMPOSE - ESTADO
# ============================================

# Obtener número de contenedores corriendo para un stack
docker::stack::get_running_count() {
    local stack="$1"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if ! docker::stack::has_compose "$stack"; then
        echo "0"
        return 0
    fi

    cd "$stack_dir" || return 1
    docker compose ps -q --status running 2>/dev/null | wc -l | tr -d ' '
}

# Verificar si un stack está corriendo (al menos un contenedor)
docker::stack::is_running() {
    local stack="$1"
    local running

    running=$(docker::stack::get_running_count "$stack")
    [[ "$running" -gt 0 ]]
}

# ============================================
# FUNCIONES DE COMPOSE - OPERACIONES
# ============================================

# Ejecutar pre-deploy script si existe
docker::stack::run_predeploy() {
    local stack="$1"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if [[ ! -f "${stack_dir}/pre-deploy.sh" ]]; then
        return 0
    fi

    logs::info "🔧 Ejecutando configuración pre-deploy para stack $stack..."

    cd "$stack_dir" || return 1

    if ./pre-deploy.sh; then
        logs::info "✅ Pre-deploy completado para stack $stack"
        return 0
    else
        logs::warn "⚠️ Error en script pre-deploy, continuando con configuración por defecto"
        return 1
    fi
}

# Parar un stack
docker::stack::down() {
    local stack="$1"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if ! docker::stack::has_compose "$stack"; then
        return 1
    fi

    cd "$stack_dir" || return 1
    docker compose down --remove-orphans
}

# Construir imágenes de un stack
docker::stack::build() {
    local stack="$1"
    local no_cache="${2:-false}"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if ! docker::stack::has_compose "$stack"; then
        return 1
    fi

    cd "$stack_dir" || return 1

    if [[ "$no_cache" == "true" ]]; then
        logs::info "🔨 Rebuilding imagen(es) desde cero (sin caché)..."
        docker compose build --no-cache
    else
        logs::info "🔨 Rebuilding imagen(es) (con caché)..."
        docker compose build
    fi
}

# Levantar un stack
docker::stack::up() {
    local stack="$1"
    local force_recreate="${2:-false}"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if ! docker::stack::has_compose "$stack"; then
        return 1
    fi

    cd "$stack_dir" || return 1

    if [[ "$force_recreate" == "true" ]]; then
        logs::info "♻️ Recreando contenedores completamente..."
        docker compose up -d --force-recreate
    else
        logs::info "🔃 Levantando con nueva configuración..."
        docker compose up -d
    fi
}

# Obtener logs de un stack
docker::stack::logs() {
    local stack="$1"
    local tail="${2:-20}"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if ! docker::stack::has_compose "$stack"; then
        return 1
    fi

    cd "$stack_dir" || return 1
    docker compose logs --tail="$tail"
}

# Mostrar estado de contenedores de un stack
docker::stack::ps() {
    local stack="$1"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if ! docker::stack::has_compose "$stack"; then
        return 1
    fi

    cd "$stack_dir" || return 1
    docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null || docker compose ps
}

# ============================================
# FUNCIONES DE COMPOSE - HEALTH CHECK
# ============================================

# Verificar salud de un stack después del despliegue
docker::stack::verify_health() {
    local stack="$1"
    local max_wait="${2:-180}"
    local stack_dir="${_DOCKER_DIR}/${stack}"

    if ! docker::stack::has_compose "$stack"; then
        return 1
    fi

    cd "$stack_dir" || return 1

    local check_interval=8
    local stabilization_wait=10

    logs::info "⏱️ Verificando salud del stack $stack (máximo ${max_wait}s)..."

    local expected_containers
    expected_containers=$(docker::stack::get_service_count "$stack")

    local elapsed_time=0
    local last_running_count=0

    # Espera inicial mínima
    sleep 5

    while [[ $elapsed_time -lt $max_wait ]]; do
        local running_containers
        running_containers=$(docker::stack::get_running_count "$stack")

        # Mostrar progreso si hay cambios
        if [[ $running_containers -ne $last_running_count ]]; then
            logs::info "📊 Stack $stack: $running_containers/$expected_containers contenedores corriendo (${elapsed_time}s)"
            last_running_count=$running_containers
        fi

        # Verificar si todos los contenedores están corriendo
        if [[ $running_containers -eq $expected_containers && $running_containers -gt 0 ]]; then
            # Espera adicional para estabilización
            logs::info "⏳ Stack $stack detectado como corriendo, esperando estabilización adicional..."
            sleep $stabilization_wait

            # Verificación final de estabilidad
            local final_check
            final_check=$(docker::stack::get_running_count "$stack")

            if [[ $final_check -eq $expected_containers ]]; then
                logs::info "✅ Stack $stack completamente estabilizado"
                return 0
            fi
        fi

        # Verificar si hay contenedores con errores críticos
        local failed_count
        failed_count=$(docker compose ps --format "table {{.State}}" 2>/dev/null | grep -c "exited\|dead\|restarting" 2>/dev/null || echo "0")

        if [[ $failed_count -gt 0 && $elapsed_time -gt 30 ]]; then
            logs::info "⚠️ Detectados contenedores con problemas en stack $stack"
            docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null | grep -E "exited|dead|restarting" || true
        fi

        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
    done

    # Timeout alcanzado
    logs::info "⏰ Timeout verificando stack $stack después de ${max_wait}s"
    logs::info "📊 Estado final: $last_running_count/$expected_containers contenedores corriendo"

    # Mostrar estado detallado
    logs::info "🔍 Estado detallado de contenedores:"
    docker::stack::ps "$stack"

    # Considerar parcialmente exitoso si al menos 80% están corriendo
    local success_threshold=$(( expected_containers * 80 / 100 ))
    if [[ $last_running_count -ge $success_threshold && $last_running_count -gt 0 ]]; then
        logs::info "⚠️ Stack $stack parcialmente funcional ($last_running_count/$expected_containers)"
        return 0
    else
        return 1
    fi
}

