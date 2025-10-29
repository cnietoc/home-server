#!/usr/bin/env bash

# Script para limpieza completa y redespliegue del home server
# Útil después de reorganizaciones de stacks o cambios mayores

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/common/env-loader.sh"

show_help() {
    cat << EOF
Uso: $0 [opciones]

DESCRIPCIÓN:
  Script de limpieza y redespliegue completo del home server.
  Útil después de reorganizaciones de stacks o cambios mayores.

PROCESO:
  1. Para TODOS los contenedores del sistema
  2. Ejecuta deploy completo desde cero
  3. Elimina contenedores huérfanos (que no se levantaron)
  4. Limpia recursos Docker no utilizados
  5. Verifica estado final

OPCIONES:
  --dry-run        Mostrar qué haría sin ejecutar
  --no-cleanup     No limpiar recursos Docker al final
  --force          No pedir confirmación
  -v, --verbose    Mostrar información detallada
  -h, --help       Mostrar esta ayuda

EJEMPLOS:
  $0               # Limpieza completa con confirmación
  $0 --dry-run     # Ver qué haría sin ejecutar
  $0 --force       # Ejecutar sin confirmación
  $0 --verbose     # Con información detallada

ADVERTENCIA:
  Este script para TODOS los contenedores y elimina recursos no utilizados.
  Úsalo solo cuando necesites una limpieza completa.
EOF
}

log_step() {
    echo ""
    log "🔄 $1"
    echo "   $(echo "$1" | sed 's/./-/g')"
}

# Obtener TODOS los contenedores (agnóstico)
get_all_containers() {
    # Obtener todos los contenedores (corriendo y parados)
    docker ps -aq 2>/dev/null || echo ""
}

# Obtener contenedores que están corriendo después del deploy
get_running_containers_after_deploy() {
    # Obtener solo los contenedores que están corriendo
    docker ps -q 2>/dev/null || echo ""
}

# Para TODOS los contenedores (agnóstico)
stop_all_containers() {
    local dry_run="$1"
    local verbose="$2"

    log_step "Parando TODOS los contenedores"

    local containers=$(get_all_containers)

    if [[ -z "$containers" ]]; then
        log "ℹ️ No hay contenedores en el sistema"
        return 0
    fi

    local container_count=$(echo "$containers" | wc -w)
    log "📦 Encontrados $container_count contenedores en total"

    if [[ "$verbose" == "true" ]]; then
        log "📦 Contenedores a parar:"
        for container_id in $containers; do
            local name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///' || echo "unknown")
            log "   - $name ($container_id)"
        done
    fi

    if [[ "$dry_run" == "true" ]]; then
        log "🔍 DRY RUN: Pararía $container_count contenedores"
        return 0
    fi

    log "⏹️ Parando todos los contenedores..."
    if [[ -n "$containers" ]]; then
        if docker stop $containers >/dev/null 2>&1; then
            log "✅ Contenedores parados exitosamente"
        else
            log "⚠️ Algunos contenedores ya estaban parados o no se pudieron parar"
        fi
    fi
}

# Eliminar contenedores huérfanos (los que no están corriendo después del deploy)
remove_orphaned_containers() {
    local dry_run="$1"
    local verbose="$2"

    log_step "Eliminando contenedores huérfanos (no corriendo)"

    # Obtener todos los contenedores (parados y corriendo)
    local all_containers=$(get_all_containers)
    # Obtener solo los que están corriendo ahora
    local running_containers=$(get_running_containers_after_deploy)

    if [[ -z "$all_containers" ]]; then
        log "ℹ️ No hay contenedores en el sistema"
        return 0
    fi

    # Encontrar contenedores que están parados (huérfanos)
    local orphaned_containers=""
    for container_id in $all_containers; do
        # Si el contenedor no está en la lista de los corriendo, es huérfano
        if ! echo "$running_containers" | grep -q "$container_id"; then
            orphaned_containers="$orphaned_containers $container_id"
        fi
    done

    orphaned_containers=$(echo "$orphaned_containers" | xargs) # Limpiar espacios

    if [[ -z "$orphaned_containers" ]]; then
        log "ℹ️ No hay contenedores huérfanos para eliminar"
        return 0
    fi

    local orphaned_count=$(echo "$orphaned_containers" | wc -w)
    log "🗑️ Encontrados $orphaned_count contenedores huérfanos"

    if [[ "$verbose" == "true" ]]; then
        log "📦 Contenedores huérfanos a eliminar:"
        for container_id in $orphaned_containers; do
            local name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///' || echo "unknown")
            log "   - $name ($container_id)"
        done
    fi

    if [[ "$dry_run" == "true" ]]; then
        log "🔍 DRY RUN: Eliminaría $orphaned_count contenedores huérfanos"
        return 0
    fi

    log "🗑️ Eliminando contenedores huérfanos..."
    if docker rm $orphaned_containers >/dev/null 2>&1; then
        log "✅ Contenedores huérfanos eliminados exitosamente"
    else
        log "⚠️ Algunos contenedores no se pudieron eliminar (puede que estén corriendo)"
    fi
}

# Limpiar recursos Docker
cleanup_docker_resources() {
    local dry_run="$1"
    local verbose="$2"
    local no_cleanup="$3"

    if [[ "$no_cleanup" == "true" ]]; then
        log "⏭️ Omitiendo limpieza de recursos Docker"
        return 0
    fi

    log_step "Limpiando recursos Docker no utilizados"

    if [[ "$dry_run" == "true" ]]; then
        log "🔍 DRY RUN: Ejecutaría 'docker system prune -f'"
        log "🔍 DRY RUN: Ejecutaría 'docker volume prune -f'"
        log "🔍 DRY RUN: Ejecutaría 'docker network prune -f'"
        return 0
    fi

    log "🧹 Limpiando imágenes huérfanas..."
    docker image prune -f >/dev/null 2>&1 || true

    log "🧹 Limpiando volúmenes huérfanos..."
    docker volume prune -f >/dev/null 2>&1 || true

    log "🧹 Limpiando redes huérfanas..."
    docker network prune -f >/dev/null 2>&1 || true

    [[ "$verbose" == "true" ]] && {
        log "📊 Estadísticas Docker después de limpieza:"
        docker system df
    }

    log "✅ Limpieza completada"
}

# Ejecutar deploy completo
run_clean_deploy() {
    local dry_run="$1"
    local verbose="$2"

    log_step "Ejecutando deploy completo"

    if [[ "$dry_run" == "true" ]]; then
        log "🔍 DRY RUN: Ejecutaría deploy completo"
        return 0
    fi

    local deploy_args=()
    [[ "$verbose" == "true" ]] && deploy_args+=("--verbose")

    log "🚀 Iniciando deploy completo..."
    if "$SCRIPT_DIR/deploy.sh" --force "${deploy_args[@]}"; then
        log "✅ Deploy completado"
    else
        error "❌ Error en deploy"
        return 1
    fi
}

# Verificar estado final
verify_final_state() {
    local verbose="$1"

    log_step "Verificando estado final"

    local running_containers=$(get_running_containers_after_deploy)
    local running_count=$(echo "$running_containers" | wc -w)

    log "📊 Estado final de contenedores:"
    if [[ $running_count -gt 0 ]]; then
        log "✅ $running_count contenedores corriendo después del deploy"
        if [[ "$verbose" == "true" ]]; then
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
        else
            docker ps --format "table {{.Names}}\t{{.Status}}"
        fi
    else
        warn "⚠️ No hay contenedores corriendo después del deploy"
    fi

    if [[ "$verbose" == "true" ]]; then
        echo ""
        log "📊 Resumen Docker:"
        docker system df

        echo ""
        log "🌐 Redes disponibles:"
        docker network ls
    fi
}

# Función principal
main() {
    local dry_run=false
    local no_cleanup=false
    local force=false
    local verbose=false

    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --no-cleanup)
                no_cleanup=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "❌ Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo "🧹 Home Server - Limpieza y Redespliegue Completo"
    echo "================================================="

    if [[ "$dry_run" == "true" ]]; then
        echo "🔍 MODO DRY RUN - Solo mostrando qué haría"
    else
        echo "⚠️ MODO EJECUCIÓN - Se realizarán cambios reales"
    fi
    echo ""

    # Mostrar qué se hará
    log "📋 Proceso a ejecutar:"
    log "   1. Parar TODOS los contenedores del sistema"
    log "   2. Ejecutar deploy completo desde cero"
    log "   3. Eliminar contenedores huérfanos (que no se levantaron)"
    if [[ "$no_cleanup" != "true" ]]; then
        log "   4. Limpiar recursos Docker no utilizados"
        log "   5. Verificar estado final"
    else
        log "   4. Verificar estado final"
    fi

    # Pedir confirmación si no es forzado
    if [[ "$force" != "true" && "$dry_run" != "true" ]]; then
        echo ""
        warn "⚠️ Este proceso parará TODOS los contenedores del sistema"
        warn "   y eliminará contenedores huérfanos y recursos no utilizados."
        read -p "¿Continuar? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "❌ Operación cancelada"
            exit 0
        fi
    fi

    echo ""
    log "🚀 Iniciando proceso de limpieza..."

    # Ejecutar pasos
    stop_all_containers "$dry_run" "$verbose"

    if [[ "$dry_run" != "true" ]]; then
        run_clean_deploy "$dry_run" "$verbose"
        remove_orphaned_containers "$dry_run" "$verbose"
        cleanup_docker_resources "$dry_run" "$verbose" "$no_cleanup"
        verify_final_state "$verbose"
    else
        # En dry-run, simular el resto de pasos
        run_clean_deploy "$dry_run" "$verbose"
        remove_orphaned_containers "$dry_run" "$verbose"
        cleanup_docker_resources "$dry_run" "$verbose" "$no_cleanup"
    fi

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        log "🔍 DRY RUN completado - No se realizaron cambios"
        log "💡 Ejecuta sin --dry-run para realizar la limpieza"
    else
        log "🎉 Limpieza y redespliegue completados exitosamente"

        if load_common_config 2>/dev/null; then
            echo ""
            log "🌐 Servicios disponibles:"
            log "   🔀 Traefik Dashboard: https://traefik.${BASE_DOMAIN:-tu-dominio.com}"
            log "   🔐 TinyAuth: https://auth.${BASE_DOMAIN:-tu-dominio.com}"
            log "   👋 Hello World: https://hello.${BASE_DOMAIN:-tu-dominio.com}"
        fi
    fi
}

main "$@"
