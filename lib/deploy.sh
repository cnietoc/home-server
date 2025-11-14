#!/usr/bin/env bash
# ============================================
# lib/deploy.sh — Librería de gestión de deployments
# Proporciona funciones para detectar cambios, generar configs y desplegar stacks
# ============================================

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente."
    exit 1
}

# --- Inicialización de variables ---
_DEPLOY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DEPLOY_PROJECT_ROOT="$(dirname "$_DEPLOY_LIB_DIR")"
_DEPLOY_DOCKER_DIR="${_DEPLOY_PROJECT_ROOT}/docker"
_DEPLOY_CONFIG_DIR="${_DEPLOY_PROJECT_ROOT}/config"

# Cargar dependencias desde lib/
source "${_DEPLOY_LIB_DIR}/logs.sh"
source "${_DEPLOY_LIB_DIR}/stack.sh"
source "${_DEPLOY_LIB_DIR}/state.sh"
source "${_DEPLOY_LIB_DIR}/docker.sh"
source "${_DEPLOY_LIB_DIR}/config.sh"

# ============================================
# FUNCIONES DE HASHING
# ============================================

# Calcular hash de toda la carpeta de un stack
deploy::stack::get_hash() {
    local stack="$1"
    local stack_dir="${_DEPLOY_DOCKER_DIR}/${stack}"

    if [[ -d "$stack_dir" ]]; then
        find "$stack_dir" -type f -print0 2>/dev/null | sort -z | xargs -0 cat 2>/dev/null | shasum -a 256 | cut -d' ' -f1
    else
        echo "no_stack"
    fi
}

# Calcular hash de archivos fuente de configuración (templates, stacks.yml, private)
deploy::config::get_sources_hash() {
    local config_files=(
        "$_DEPLOY_CONFIG_DIR/templates"
        "$_DEPLOY_CONFIG_DIR/stacks.yml"
    )

    # Incluir archivos de configuración privada si existe el enlace
    if [[ -L "$_DEPLOY_CONFIG_DIR/private" ]]; then
        config_files+=("$_DEPLOY_CONFIG_DIR/private")
    fi

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

    echo "$temp_content" | shasum -a 256 | cut -d' ' -f1
}

# ============================================
# FUNCIONES DE DETECCIÓN DE CAMBIOS
# ============================================

# Verificar si han cambiado los archivos de un stack
deploy::stack::has_changed() {
    local stack="$1"
    local current_hash
    local stored_hash

    current_hash=$(deploy::stack::get_hash "$stack")
    stored_hash=$(state::stack::get_deployment_hash "$stack")

    [[ "$current_hash" != "$stored_hash" ]]
}

# Verificar si han cambiado archivos fuente de configuración
deploy::config::sources_have_changed() {
    local current_hash
    local stored_hash

    current_hash=$(deploy::config::get_sources_hash)
    stored_hash=$(state::server::get_config_hash)

    [[ "$current_hash" != "$stored_hash" ]]
}

# Obtener lista de stacks que han cambiado
deploy::stack::list_changed() {
    local changed_stacks=()

    # Obtener todos los stacks disponibles
    local all_stacks
    all_stacks=$(stack::list)

    while IFS= read -r stack; do
        [[ -z "$stack" ]] && continue

        # Verificar que el stack existe en docker/
        if ! docker::stack::exists "$stack"; then
            continue
        fi

        # Verificar si ha cambiado
        if deploy::stack::has_changed "$stack"; then
            changed_stacks+=("$stack")
        fi
    done <<< "$all_stacks"

    printf "%s\n" "${changed_stacks[@]}"
}

# ============================================
# FUNCIONES DE GENERACIÓN DE CONFIGS
# ============================================

# Regenerar archivos .env si hay cambios en fuentes de configuración
deploy::config::regenerate_envs() {
    shift
    local stacks=("$@")

    # Verificar si han cambiado fuentes de configuración
    if ! deploy::config::sources_have_changed; then
        return 1
    fi

    logs::info "🔄 Regenerando archivos .env (detectados cambios en configuración)..."

    # Generar .env usando la librería config
    if ! config::generate_multiple_envs "${stacks[@]}"; then
        logs::error "Error regenerando archivos .env"
        return 1
    fi

    # Guardar nuevo hash de fuentes de configuración
    local new_hash
    new_hash=$(deploy::config::get_sources_hash)
    state::server::update_config_hash "$new_hash"

    return 0
}

deploy::stack::pre_deploy() {
    local stack="$1"
    local stack_dir="${_DEPLOY_DOCKER_DIR}/${stack}"

    if [[ ! -f "${stack_dir}/pre-deploy.sh" ]]; then
        return 0
    fi

    logs::info "🔧 Ejecutando configuración pre-deploy para stack $stack..."

    cd "$stack_dir" || return 1

    # Ejecutar y mostrar output en tiempo real
    if bash ./pre-deploy.sh; then
        logs::info "✅ Pre-deploy completado para stack $stack"
        return 0
    else
        logs::warn "⚠️ Error en script pre-deploy, continuando con configuración por defecto"
        return 1
    fi
}


# ============================================
# FUNCIONES DE DEPLOYMENT
# ============================================

# Desplegar un stack completo
deploy::stack::deploy() {
    local stack="$1"
    local force_recreate="${2:-false}"

    if ! docker::stack::exists "$stack"; then
        logs::error "❌ Stack no encontrado: $stack"
        return 1
    fi

    if ! docker::stack::has_compose "$stack"; then
        logs::error "❌ No existe docker-compose.yml en: $stack"
        return 1
    fi

    logs::info "🔄 Desplegando stack: $stack"

    # Ejecutar pre-deploy si existe
    deploy::stack::pre_deploy "$stack" || true

    # Parar contenedores actuales
    logs::info "⏹️ Parando contenedores actuales..."
    docker::stack::down "$stack"

    # Build si es necesario
    if docker::stack::needs_build "$stack"; then
        if [[ "$force_recreate" == "true" ]]; then
            docker::stack::build "$stack" true
        else
            docker::stack::build "$stack" false
        fi
    fi

    # Levantar contenedores
    docker::stack::up "$stack" "$force_recreate"

    # Verificación rápida inicial
    logs::info "🔍 Verificando inicio de contenedores..."
    sleep 3

    local quick_check
    quick_check=$(docker::stack::get_running_count "$stack")

    if [[ $quick_check -eq 0 ]]; then
        logs::error "❌ Ningún contenedor iniciado para stack $stack"
        logs::info "🔍 Logs de error:"
        docker::stack::logs "$stack" 20
        return 1
    fi

    logs::info "✅ Stack $stack iniciado (contenedores detectados)"

    # Verificar salud del stack
    local health_result=0
    docker::stack::verify_health "$stack" 90 || health_result=$?

    if [[ $health_result -eq 0 ]]; then
        logs::info "✅ Stack $stack desplegado y funcionando correctamente"

        # Guardar estado del deployment
        local hash
        hash=$(deploy::stack::get_hash "$stack")
        state::stack::update_deployment "$stack" "$hash"

        return 0
    else
        logs::warn "⚠️ Stack $stack desplegado pero con posibles problemas de salud"
        return 1
    fi
}


# Desplegar múltiples stacks
deploy::stacks::deploy_multiple() {
    local force_recreate="${1:-false}"
    shift
    local stacks=("$@")

    if [[ ${#stacks[@]} -eq 0 ]]; then
        logs::info "⚠️ No hay stacks para desplegar"
        return 0
    fi

    logs::info "🎯 Desplegando stacks: ${stacks[*]}"

    local success=0
    local total=${#stacks[@]}
    local failed_stacks=()

    for stack in "${stacks[@]}"; do
        # Desplegar el stack (ahora incluye verificación de salud y guardado de estado)
        if deploy::stack::deploy "$stack" "$force_recreate"; then
            success=$((success + 1))
        else
            failed_stacks+=("$stack")
        fi
    done

    # Actualizar deployment global
    state::server::update_deployment

    # Retornar resultados
    echo "$success $total ${failed_stacks[*]}"
}

# ============================================
# FUNCIONES DE SELECCIÓN DE STACKS
# ============================================

# Obtener stacks que están habilitados pero no corriendo
deploy::stacks::get_stopped() {
    local force="${1:-false}"
    local all_stacks
    all_stacks=$(stack::list)

    local stopped_stacks=()
    while IFS= read -r stack; do
        [[ -z "$stack" ]] && continue

        # Verificar si el stack está habilitado (o si se usa --force)
        if [[ "$force" == "true" ]] || state::stack::is_enabled "$stack"; then
            # Verificar si el stack está detenido
            if ! docker::stack::is_running "$stack"; then
                stopped_stacks+=("$stack")
            fi
        fi
    done <<< "$all_stacks"

    # Retornar lista de stacks detenidos
    printf "%s\n" "${stopped_stacks[@]}"
}

# Filtrar stacks habilitados de una lista
# Retorna dos líneas: primera con habilitados, segunda con deshabilitados
deploy::stacks::filter_enabled() {
    local stacks=("$@")
    local enabled_stacks=()
    local skipped_stacks=()

    for stack in "${stacks[@]}"; do
        if state::stack::is_enabled "$stack"; then
            enabled_stacks+=("$stack")
        else
            skipped_stacks+=("$stack")
        fi
    done

    # Retornar habilitados en primera línea, deshabilitados en segunda
    printf "%s\n" "${enabled_stacks[*]}"
    printf "%s\n" "${skipped_stacks[*]}"
}

# Determinar qué stacks desplegar basándose en opciones
deploy::stacks::determine() {
    local force="${1:-false}"
    shift
    local specified_stacks=("$@")

    local stacks_to_deploy=()

    # Si no se especificaron stacks
    if [[ ${#specified_stacks[@]} -eq 0 ]]; then
        if [[ "$force" == "true" ]]; then
            # Forzar despliegue de todos los stacks
            logs::info "📦 Desplegando todos los stacks (forzado)..."

            local all_stacks
            all_stacks=$(stack::list)

            while IFS= read -r stack; do
                [[ -z "$stack" ]] && continue
                if docker::stack::exists "$stack"; then
                    stacks_to_deploy+=("$stack")
                fi
            done <<< "$all_stacks"
        else
            # Detectar automáticamente stacks con cambios
            local changed_stacks
            changed_stacks=$(deploy::stack::list_changed)

            if [[ -n "$changed_stacks" ]]; then
                while IFS= read -r stack; do
                    [[ -z "$stack" ]] && continue
                    stacks_to_deploy+=("$stack")
                done <<< "$changed_stacks"
                logs::info "📦 Desplegando stacks con cambios detectados: ${stacks_to_deploy[*]}"
            else
                logs::info "⏭️ No hay cambios detectados en ningún stack."
                return 1
            fi
        fi
    else
        # Se especificaron stacks específicos
        if [[ "$force" == "true" ]]; then
            # Forzar todos los especificados
            stacks_to_deploy=("${specified_stacks[@]}")
        else
            # Verificar cuáles han cambiado
            local specified_changed=()
            local specified_unchanged=()

            for stack in "${specified_stacks[@]}"; do
                if deploy::stack::has_changed "$stack"; then
                    specified_changed+=("$stack")
                else
                    specified_unchanged+=("$stack")
                fi
            done

            if [[ ${#specified_changed[@]} -gt 0 ]]; then
                logs::info "📦 De los stacks especificados, tienen cambios: ${specified_changed[*]}"
            fi

            if [[ ${#specified_unchanged[@]} -gt 0 ]]; then
                logs::info "⏭️ Sin cambios (se omiten): ${specified_unchanged[*]}" >&2
                logs::info "💡 Usa --force para desplegar todos los especificados sin importar cambios" >&2
            fi

            stacks_to_deploy=("${specified_changed[@]}")
        fi
    fi

    # Retornar lista de stacks
    printf "%s\n" "${stacks_to_deploy[@]}"
}
