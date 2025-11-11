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
  2. Elimina TODOS los contenedores (limpieza total)
  3. Elimina TODAS las imágenes Docker descargadas
  4. Elimina TODAS las redes personalizadas
  5. Elimina TODOS los volúmenes no utilizados
  6. Limpia cache de build y recursos huérfanos
  7. Ejecuta deploy completo desde cero
  8. Verifica estado final

OPCIONES:
  --dry-run        Mostrar qué haría sin ejecutar
  --no-cleanup     No limpiar recursos Docker al final
  --keep-images    No eliminar imágenes Docker (mantener para acelerar re-deploy)
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

# Obtener contenedores que están corriendo después del deploy
get_running_containers_after_deploy() {
    # Obtener solo los contenedores que están corriendo
    docker ps -q 2>/dev/null || echo ""
}

# Limpiar TODOS los recursos Docker
cleanup_all_docker_resources() {
    local dry_run="$1"
    local verbose="$2"
    local no_cleanup="$3"
    local keep_images="$4"

    if [[ "$no_cleanup" == "true" ]]; then
        log "⏭️ Omitiendo limpieza de recursos Docker"
        return 0
    fi

    log_step "Limpieza COMPLETA de recursos Docker"

    if [[ "$dry_run" == "true" ]]; then
        log "🔍 DRY RUN: Limpieza completa que se ejecutaría:"
        log "   - Parar y eliminar TODOS los contenedores"
        if [[ "$keep_images" != "true" ]]; then
            log "   - Eliminar TODAS las imágenes Docker"
        fi
        log "   - Eliminar TODAS las redes personalizadas"
        log "   - Eliminar TODOS los volúmenes"
        log "   - Limpiar cache de build"
        log "   - Limpiar recursos huérfanos"
        return 0
    fi

    # Mostrar estado inicial si es verbose
    if [[ "$verbose" == "true" ]]; then
        log "📊 Estado inicial del sistema Docker:"
        docker system df 2>/dev/null || true
        echo ""
    fi

    # 1. Parar TODOS los contenedores
    log "🛑 Parando TODOS los contenedores..."
    local running_containers=$(docker ps -q 2>/dev/null || echo "")
    if [[ -n "$running_containers" ]]; then
        docker stop $running_containers >/dev/null 2>&1 || true
        docker kill $running_containers >/dev/null 2>&1 || true
        log "✅ Contenedores parados"
    else
        log "ℹ️ No hay contenedores corriendo"
    fi

    # 2. Eliminar TODOS los contenedores
    log "🗑️ Eliminando TODOS los contenedores..."
    local all_containers=$(docker ps -aq 2>/dev/null || echo "")
    if [[ -n "$all_containers" ]]; then
        docker rm -f $all_containers >/dev/null 2>&1 || true
        log "✅ Contenedores eliminados"
    else
        log "ℹ️ No hay contenedores para eliminar"
    fi

    # 3. Eliminar TODAS las imágenes (si no se especifica mantenerlas)
    if [[ "$keep_images" != "true" ]]; then
        log "🖼️ Eliminando TODAS las imágenes Docker..."
        local all_images=$(docker images -q 2>/dev/null || echo "")
        if [[ -n "$all_images" ]]; then
            # Primero intentar eliminar imágenes no utilizadas
            docker image prune -a -f >/dev/null 2>&1 || true

            # Luego forzar eliminación de todas las imágenes restantes
            local remaining_images=$(docker images -q 2>/dev/null || echo "")
            if [[ -n "$remaining_images" ]]; then
                docker rmi -f $remaining_images >/dev/null 2>&1 || true
            fi

            log "✅ Imágenes eliminadas"
        else
            log "ℹ️ No hay imágenes para eliminar"
        fi
    else
        log "💾 Manteniendo imágenes Docker (--keep-images especificado)"
    fi

    # 4. Eliminar TODAS las redes personalizadas
    log "🌐 Eliminando TODAS las redes personalizadas..."
    # Obtener redes personalizadas (excluyendo las del sistema: bridge, host, none)
    local custom_networks=$(docker network ls --format "{{.ID}}" --filter "type=custom" 2>/dev/null || echo "")
    if [[ -n "$custom_networks" ]]; then
        docker network rm $custom_networks >/dev/null 2>&1 || true
        log "✅ Redes personalizadas eliminadas"
    else
        log "ℹ️ No hay redes personalizadas para eliminar"
    fi

    # También limpiar redes huérfanas con prune
    docker network prune -f >/dev/null 2>&1 || true

    # 5. Eliminar TODOS los volúmenes
    log "💽 Eliminando TODOS los volúmenes..."
    local all_volumes=$(docker volume ls -q 2>/dev/null || echo "")
    if [[ -n "$all_volumes" ]]; then
        docker volume rm $all_volumes >/dev/null 2>&1 || true
        log "✅ Volúmenes eliminados"
    else
        log "ℹ️ No hay volúmenes para eliminar"
    fi

    # También usar prune para asegurar limpieza completa
    docker volume prune -f >/dev/null 2>&1 || true

    # 6. Limpiar cache de build y recursos huérfanos
    log "🧹 Limpiando cache de build y recursos huérfanos..."

    # Limpiar build cache
    docker builder prune -a -f >/dev/null 2>&1 || true

    # Limpieza general del sistema (esto debería limpiar cualquier cosa restante)
    docker system prune -a -f --volumes >/dev/null 2>&1 || true

    log "✅ Cache y recursos huérfanos eliminados"

    # Verificación final
    if [[ "$verbose" == "true" ]]; then
        echo ""
        log "📊 Estado final del sistema Docker:"
        docker system df 2>/dev/null || true

        echo ""
        log "📈 Resumen de limpieza:"
        local final_containers=$(docker ps -aq 2>/dev/null | wc -l)
        local final_images=$(docker images -q 2>/dev/null | wc -l)
        local final_volumes=$(docker volume ls -q 2>/dev/null | wc -l)
        local final_networks=$(docker network ls --filter "type=custom" -q 2>/dev/null | wc -l)

        log "   - Contenedores restantes: $final_containers"
        log "   - Imágenes restantes: $final_images"
        log "   - Volúmenes restantes: $final_volumes"
        log "   - Redes personalizadas restantes: $final_networks"
    fi

    log "🎯 Limpieza COMPLETA del sistema Docker finalizada"
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
    local keep_images=false
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
            --keep-images)
                keep_images=true
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
    log "   2. Eliminar TODOS los contenedores"
    log "   3. Eliminar TODAS las redes personalizadas"
    if [[ "$keep_images" != "true" ]]; then
        log "   4. Eliminar TODAS las imágenes Docker"
    else
        log "   4. Mantener imágenes Docker (--keep-images)"
    fi
    log "   5. Eliminar TODOS los volúmenes"
    log "   6. Limpiar cache de build y recursos huérfanos"
    log "   7. Ejecutar deploy completo desde cero"
    log "   8. Verificar estado final"

    # Pedir confirmación si no es forzado
    if [[ "$force" != "true" && "$dry_run" != "true" ]]; then
        echo ""
        warn "⚠️ ATENCIÓN: Este proceso eliminará TODO el contenido Docker:"
        warn "   - TODOS los contenedores (corriendo y parados)"
        warn "   - TODAS las redes personalizadas"
        if [[ "$keep_images" != "true" ]]; then
            warn "   - TODAS las imágenes descargadas"
        fi
        warn "   - TODOS los volúmenes de datos"
        warn "   - TODO el cache de build"
        warn ""
        warn "⚠️ Esto significa que tendrás que volver a descargar todas las imágenes"
        warn "   y recrear todos los volúmenes desde cero."
        echo ""
        read -p "¿Estás SEGURO de que quieres continuar? (escriba 'SI' para confirmar): " -r
        echo ""
        if [[ $REPLY != "SI" ]]; then
            log "❌ Operación cancelada"
            log "💡 Usa --keep-images si quieres mantener las imágenes descargadas"
            exit 0
        fi
    fi

    echo ""
    log "🚀 Iniciando proceso de limpieza COMPLETA..."

    # Ejecutar limpieza COMPLETA antes del deploy
    cleanup_all_docker_resources "$dry_run" "$verbose" "$no_cleanup" "$keep_images"

    if [[ "$dry_run" != "true" ]]; then
        run_clean_deploy "$dry_run" "$verbose"
        verify_final_state "$verbose"
    else
        # En dry-run, simular el resto de pasos
        run_clean_deploy "$dry_run" "$verbose"
    fi

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        log "🔍 DRY RUN completado - No se realizaron cambios"
        log "💡 Ejecuta sin --dry-run para realizar la limpieza COMPLETA"
        if [[ "$keep_images" != "true" ]]; then
            log "💡 Usa --keep-images si quieres mantener las imágenes Docker"
        fi
    else
        log "🎉 Limpieza COMPLETA y redespliegue completados exitosamente"

        echo ""
        # Mostrar servicios usando el script centralizado - detectar stacks dinámicamente
        local available_stacks
        available_stacks=$(find "$PROJECT_ROOT/docker" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null | sort)

        if [[ -n "$available_stacks" ]]; then
            # Convertir a array para pasar como argumentos
            local stacks_array=($available_stacks)
            "$SCRIPT_DIR/stack-info.sh" services "${stacks_array[@]}" 2>/dev/null || {
                log "ℹ️ No se pudo cargar información de servicios"
            }
        else
            log "ℹ️ No se encontraron stacks desplegados"
        fi

        if [[ "$keep_images" != "true" ]]; then
            echo ""
            log "⏱️ Nota: Como se eliminaron todas las imágenes, el primer deploy"
            log "   puede tardar más tiempo descargando las imágenes de nuevo."
        fi
    fi
}

main "$@"
