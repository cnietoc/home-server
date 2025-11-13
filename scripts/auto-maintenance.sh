#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CRON_LOG="$PROJECT_ROOT/data/logs/maintenance.log"

source "$SCRIPT_DIR/common/env-loader.sh"
source "$SCRIPT_DIR/state.sh" 2>/dev/null || true  # Cargar funciones de estado (no fallar si no está disponible)
source "$SCRIPT_DIR/state.sh" 2>/dev/null || true  # Cargar funciones de estado (no fallar si no está disponible)

show_help() {
    cat << EOF
Uso: $0 [opciones]

DESCRIPCIÓN:
  Configura tareas automáticas (cron) para mantener el DNS actualizado y servicios funcionando.

OPCIONES:
  --install           Instalar tareas cron
  --uninstall         Desinstalar tareas cron
  --status            Ver estado de tareas cron
  --run-now           Ejecutar mantenimiento manual ahora
  --logs              Ver logs de ejecuciones automáticas
  -h, --help          Mostrar esta ayuda

TAREAS QUE SE CONFIGURAN:
  - DNS + Servicios: cada 30 minutos
  - Mantenimiento diario: 2:00 AM (sin backup)
  - Mantenimiento semanal: Domingos 3:00 AM (backup + limpieza)
  - Recuperación al inicio: Si el PC estuvo apagado

EJEMPLOS:
  $0 --install        # Configurar tareas automáticas
  $0 --status         # Ver si están corriendo
  $0 --logs           # Ver logs de ejecuciones
  $0 --run-now        # Ejecutar manualmente
EOF
}

# Crear estructura de logs
setup_logs() {
    local logs_dir="$PROJECT_ROOT/data/logs"
    mkdir -p "$logs_dir"

    # Crear archivo de log si no existe
    if [[ ! -f "$CRON_LOG" ]]; then
        touch "$CRON_LOG"
        log "✅ Archivo de log creado: $CRON_LOG"
    fi
}

# Función para logging con timestamp
cron_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$CRON_LOG"
}

# Ejecutar actualización de DNS automática
run_dns_update() {
    cron_log "🔄 Iniciando actualización automática de DNS..."

    # Cargar configuración
    if ! load_common_config || ! load_config "cloudflare"; then
        cron_log "❌ Error cargando configuración DNS"
        return 1
    fi

    # Ejecutar script de DNS y agregar salida directamente al log
    if "$SCRIPT_DIR/update-dns.sh" >> "$CRON_LOG" 2>&1; then
        cron_log "✅ Actualización DNS completada"
    else
        cron_log "❌ Error en actualización DNS"
        return 1
    fi
}

# Verificar que los servicios estén corriendo
check_services() {
    cron_log "🔍 Verificando estado de servicios..."

    local services_down=()

    # Usar stack-info.sh para obtener lista de stacks
    local available_stacks
    available_stacks=$("$SCRIPT_DIR/stack-info.sh" get_available_stacks 2>/dev/null || echo "")

    if [[ -n "$available_stacks" ]]; then
        while IFS= read -r stack_name; do
            [[ -z "$stack_name" ]] && continue

            local stack_dir="$PROJECT_ROOT/docker/$stack_name"
            if [[ -d "$stack_dir" && -f "$stack_dir/docker-compose.yml" ]]; then
                cd "$stack_dir"
                local running_containers
                running_containers=$(docker compose ps -q 2>/dev/null | wc -l)

                if [[ $running_containers -eq 0 ]]; then
                    services_down+=("$stack_name")
                    cron_log "⚠️ Stack $stack_name no está corriendo"
                else
                    cron_log "✅ Stack $stack_name corriendo ($running_containers contenedores)"
                fi
            else
                cron_log "⚠️ Stack $stack_name configurado pero directorio docker no encontrado"
            fi
        done <<< "$available_stacks"
    else
        cron_log "❌ No se pudieron obtener stacks desde stack-info.sh"
        cron_log "   Fallback: buscando directorios docker manualmente"

        # Fallback al método anterior si stack-info.sh falla
        local docker_dirs=("$PROJECT_ROOT/docker"/*)
        for stack_dir in "${docker_dirs[@]}"; do
            if [[ -d "$stack_dir" && -f "$stack_dir/docker-compose.yml" ]]; then
                local stack_name="$(basename "$stack_dir")"

                cd "$stack_dir"
                local running_containers
                running_containers=$(docker compose ps -q 2>/dev/null | wc -l)

                if [[ $running_containers -eq 0 ]]; then
                    services_down+=("$stack_name")
                    cron_log "⚠️ Stack $stack_name no está corriendo"
                else
                    cron_log "✅ Stack $stack_name corriendo ($running_containers contenedores)"
                fi
            fi
        done
    fi

    if [[ ${#services_down[@]} -gt 0 ]]; then
        cron_log "❌ Servicios caídos detectados: ${services_down[*]}"

        # Opcional: intentar reinicios automáticos
        # for service in "${services_down[@]}"; do
        #     cron_log "🔄 Intentando reiniciar $service..."
        #     cd "$PROJECT_ROOT/docker/$service"
        #     docker compose up -d >> "$CRON_LOG" 2>&1
        # done

        return 1
    else
        cron_log "✅ Todos los servicios están corriendo correctamente"
    fi
}

# Ejecutar backup automático
run_backup() {
    cron_log "💾 Iniciando backup automático..."

    # Ejecutar backup de todos los stacks con limpieza automática y modo seguro
    if "$SCRIPT_DIR/backup.sh" --all --cleanup 3 --safe >> "$CRON_LOG" 2>&1; then
        cron_log "✅ Backup automático completado"
    else
        cron_log "❌ Error durante el backup automático"
        return 1
    fi
}

# Limpiar logs antiguos
cleanup_logs() {
    cron_log "🧹 Limpiando logs antiguos..."

    # Mantener solo los últimos 30 días de logs
    find "$PROJECT_ROOT/data/logs" -name "*.log" -type f -mtime +30 -delete 2>/dev/null || true

    # Rotar log actual si es muy grande (>10MB)
    if [[ -f "$CRON_LOG" ]] && [[ $(stat -f%z "$CRON_LOG" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        mv "$CRON_LOG" "$CRON_LOG.old"
        touch "$CRON_LOG"
        cron_log "📋 Log rotado por tamaño"
    fi

    cron_log "✅ Limpieza de logs completada"
}

# Generar entradas de crontab
generate_cron_entries() {
    cat << EOF
# Home Server - Automatización DNS, servicios y backups
# Instalado: $(date)

# EJECUCIÓN AL INICIO DEL SISTEMA (recupera tareas perdidas)
@reboot sleep 60 && $SCRIPT_DIR/auto-maintenance.sh --startup >/dev/null 2>&1

# Actualización DNS + verificación de servicios cada 30 minutos
*/30 * * * * $SCRIPT_DIR/auto-maintenance.sh --periodic >/dev/null 2>&1

# Mantenimiento diario (2:00 AM) - Sin backup
0 2 * * * $SCRIPT_DIR/auto-maintenance.sh --daily >/dev/null 2>&1

# Mantenimiento semanal (Domingo 3:00 AM) - Backup + limpieza
0 3 * * 0 $SCRIPT_DIR/auto-maintenance.sh --weekly >/dev/null 2>&1

EOF
}

# Instalar tareas cron
install_cron() {
    setup_logs

    log "🔧 Instalando tareas automáticas..."

    # Respaldar crontab actual
    local backup_file="/tmp/crontab_backup_$(date +%Y%m%d_%H%M%S)"
    if crontab -l > "$backup_file" 2>/dev/null; then
        log "📁 Crontab respaldado en: $backup_file"
    fi

    # Generar nueva configuración
    local temp_cron="/tmp/home_server_cron"

    # Mantener entradas existentes (sin las nuestras)
    if crontab -l 2>/dev/null | grep -v "# Home Server - Automatización" > "$temp_cron"; then
        log "📋 Manteniendo entradas cron existentes"
    else
        touch "$temp_cron"
    fi

    # Añadir nuestras entradas
    echo "" >> "$temp_cron"
    generate_cron_entries >> "$temp_cron"

    # Instalar nueva configuración
    if crontab "$temp_cron"; then
        log "✅ Tareas automáticas instaladas"
        rm -f "$temp_cron"

        log "📋 Tareas configuradas:"
        log "   - DNS + Servicios: cada 30 minutos"
        log "   - Mantenimiento diario: 2:00 AM (sin backup)"
        log "   - Mantenimiento semanal: Domingos 3:00 AM (backup + limpieza)"

        cron_log "🎉 Sistema de automatización instalado"
    else
        log "❌ Error instalando crontab"
        rm -f "$temp_cron"
        return 1
    fi
}

# Desinstalar tareas cron
uninstall_cron() {
    log "🗑️ Desinstalando tareas automáticas..."

    local temp_cron="/tmp/home_server_cron_clean"

    # Filtrar nuestras entradas
    if crontab -l 2>/dev/null | grep -v "# Home Server - Automatización" | grep -v "auto-maintenance.sh" > "$temp_cron"; then
        if crontab "$temp_cron"; then
            log "✅ Tareas automáticas desinstaladas"
            cron_log "🗑️ Sistema de automatización desinstalado"
        else
            log "❌ Error desinstalando crontab"
            rm -f "$temp_cron"
            return 1
        fi
    else
        # No hay otras entradas, limpiar completamente
        crontab -r 2>/dev/null || true
        log "✅ Crontab limpiado completamente"
    fi

    rm -f "$temp_cron"
}

# Ver estado de tareas cron
show_status() {
    log "📊 Estado de tareas automáticas:"

    if crontab -l 2>/dev/null | grep -q "auto-maintenance.sh"; then
        log "✅ Tareas automáticas instaladas"
        echo ""
        log "📋 Entradas actuales:"
        crontab -l 2>/dev/null | grep -E "(Home Server|auto-maintenance)" || log "⚠️ No se encontraron entradas"

        echo ""
        log "📊 Últimas ejecuciones:"
        if [[ -f "$CRON_LOG" ]]; then
            tail -10 "$CRON_LOG" | head -5
        else
            log "📁 No hay logs disponibles"
        fi
    else
        log "❌ Tareas automáticas NO instaladas"
        log "Ejecuta: $0 --install para configurarlas"
    fi
}

# Ver logs completos
show_logs() {
    if [[ -f "$CRON_LOG" ]]; then
        log "📋 Últimos logs de automatización:"
        echo ""
        tail -50 "$CRON_LOG"
    else
        log "📁 No hay logs disponibles"
        log "Las tareas automáticas crearán logs cuando se ejecuten"
    fi
}

# Verificar si necesita ejecutar tareas perdidas por apagado
check_missed_tasks() {
    local daily_marker="$PROJECT_ROOT/data/logs/daily_marker"
    local weekly_marker="$PROJECT_ROOT/data/logs/weekly_marker"

    local today=$(date +%Y%m%d)
    local this_week=$(date +%Y-W%U)

    local last_daily=""
    local last_weekly=""

    # Leer marcas temporales
    if [[ -f "$daily_marker" ]]; then
        last_daily=$(cat "$daily_marker" 2>/dev/null || echo "")
    fi

    if [[ -f "$weekly_marker" ]]; then
        last_weekly=$(cat "$weekly_marker" 2>/dev/null || echo "")
    fi

    # SIEMPRE ejecutar tareas periódicas al inicio (DNS + servicios)
    # No hace falta verificar tiempo, son tareas rápidas y críticas
    cron_log "🔄 Ejecutando tareas periódicas al arranque"
    run_dns_update
    check_services

    # Verificar si hay que ejecutar daily (si no se ha hecho hoy)
    if [[ "$last_daily" != "$today" ]]; then
        cron_log "📅 Ejecutando mantenimiento diario (no se ejecutó hoy)"
        # Ya se ejecutaron DNS + servicios arriba, solo actualizamos marca
        echo "$today" > "$daily_marker"
    else
        cron_log "✅ Mantenimiento diario ya ejecutado hoy"
    fi

    # Verificar si hay que ejecutar weekly (si no se ha hecho esta semana)
    if [[ "$last_weekly" != "$this_week" ]]; then
        cron_log "📦 Ejecutando mantenimiento semanal (no se ejecutó esta semana)"
        run_backup
        cleanup_logs
        echo "$this_week" > "$weekly_marker"
    else
        cron_log "✅ Mantenimiento semanal ya ejecutado esta semana"
    fi
}

# Ejecución al inicio del sistema
run_startup() {
    setup_logs
    cron_log "🚀 Iniciando recuperación al arranque del sistema..."

    # Esperar a que la red esté disponible
    local max_wait=60
    local count=0

    while ! ping -c 1 8.8.8.8 >/dev/null 2>&1 && [[ $count -lt $max_wait ]]; do
        sleep 5
        ((count += 5))
        cron_log "⏳ Esperando conectividad de red... (${count}s)"
    done

    if [[ $count -ge $max_wait ]]; then
        cron_log "❌ No hay conectividad de red después de ${max_wait}s"
        return 1
    fi

    cron_log "🌐 Conectividad de red confirmada"

    # Verificar y recuperar tareas perdidas
    check_missed_tasks

    cron_log "✅ Recuperación al arranque completada"
}



# Ejecución periódica (cada 30 min): DNS + Servicios
run_periodic() {
    setup_logs
    cron_log "🔄 Ejecutando tareas periódicas (DNS + servicios)..."

    run_dns_update
    check_services

    cron_log "✅ Tareas periódicas completadas"
}

# Mantenimiento diario (2:00 AM): Solo mantenimiento básico, SIN backup
run_daily() {
    setup_logs

    local daily_marker="$PROJECT_ROOT/data/logs/daily_marker"
    local today=$(date +%Y%m%d)
    local last_daily=""

    if [[ -f "$daily_marker" ]]; then
        last_daily=$(cat "$daily_marker" 2>/dev/null || echo "")
    fi

    if [[ "$last_daily" == "$today" ]]; then
        cron_log "ℹ️ Mantenimiento diario ya ejecutado hoy"
        return 0
    fi

    cron_log "📅 Ejecutando mantenimiento diario para $today"

    # Registrar inicio en el estado
    update_maintenance_status "daily" "running" 2>/dev/null || true

    # Solo DNS y verificación de servicios (backup es semanal)
    local exit_code=0
    run_dns_update || exit_code=$?
    check_services || exit_code=$?

    # Marcar como completado
    echo "$today" > "$daily_marker"

    # Actualizar estado según resultado
    if [[ $exit_code -eq 0 ]]; then
        update_maintenance_status "daily" "success" 2>/dev/null || true
        cron_log "✅ Mantenimiento diario completado"
    else
        update_maintenance_status "daily" "failed" 2>/dev/null || true
        cron_log "⚠️ Mantenimiento diario completado con errores"
    fi
}

# Mantenimiento semanal (Domingo 3:00 AM): Backup + Limpieza
run_weekly() {
    setup_logs

    local weekly_marker="$PROJECT_ROOT/data/logs/weekly_marker"
    local this_week=$(date +%Y-W%U)
    local last_weekly=""

    if [[ -f "$weekly_marker" ]]; then
        last_weekly=$(cat "$weekly_marker" 2>/dev/null || echo "")
    fi

    if [[ "$last_weekly" == "$this_week" ]]; then
        cron_log "ℹ️ Mantenimiento semanal ya ejecutado esta semana"
        return 0
    fi

    cron_log "📅 Ejecutando mantenimiento semanal para semana $this_week"

    # Registrar inicio en el estado
    update_maintenance_status "weekly" "running" 2>/dev/null || true

    # Ejecutar backup y limpieza
    local exit_code=0
    run_backup || exit_code=$?
    cleanup_logs || exit_code=$?

    # También ejecutar tareas básicas
    run_dns_update || exit_code=$?
    check_services || exit_code=$?

    # Marcar como completado
    echo "$this_week" > "$weekly_marker"

    # Actualizar estado según resultado
    if [[ $exit_code -eq 0 ]]; then
        update_maintenance_status "weekly" "success" 2>/dev/null || true
        cron_log "✅ Mantenimiento semanal completado"
    else
        update_maintenance_status "weekly" "failed" 2>/dev/null || true
        cron_log "⚠️ Mantenimiento semanal completado con errores"
    fi
}

# Ejecutar mantenimiento manual
run_maintenance() {
    local dns_only=false
    local check_only=false
    local cleanup_only=false
    local backup_only=false
    local startup=false
    local daily=false
    local weekly=false
    local periodic=false

    # Parsear sub-argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dns-only)
                dns_only=true
                shift
                ;;
            --check-only)
                check_only=true
                shift
                ;;
            --cleanup-only)
                cleanup_only=true
                shift
                ;;
            --backup-only)
                backup_only=true
                shift
                ;;
            --startup)
                startup=true
                shift
                ;;
            --daily)
                daily=true
                shift
                ;;
            --weekly)
                weekly=true
                shift
                ;;
            --periodic)
                periodic=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ "$startup" == "true" ]]; then
        run_startup
    elif [[ "$periodic" == "true" ]]; then
        run_periodic
    elif [[ "$daily" == "true" ]]; then
        run_daily
    elif [[ "$weekly" == "true" ]]; then
        run_weekly
    elif [[ "$dns_only" == "true" ]]; then
        setup_logs
        run_dns_update
    elif [[ "$check_only" == "true" ]]; then
        setup_logs
        check_services
    elif [[ "$backup_only" == "true" ]]; then
        setup_logs
        run_backup
    elif [[ "$cleanup_only" == "true" ]]; then
        setup_logs
        cleanup_logs
    else
        # Mantenimiento completo manual (ejecuta todo)
        setup_logs
        cron_log "🚀 Iniciando mantenimiento completo manual..."
        run_dns_update
        run_backup
        check_services
        cleanup_logs
        cron_log "✅ Mantenimiento completo terminado"
    fi
}

# Función principal
main() {
    case "${1:-}" in
        --install)
            install_cron
            ;;
        --uninstall)
            uninstall_cron
            ;;
        --status)
            show_status
            ;;
        --logs)
            show_logs
            ;;
        --run-now)
            shift
            run_maintenance "$@"
            ;;
        --dns-only|--check-only|--cleanup-only|--backup-only|--startup|--daily|--weekly|--periodic)
            run_maintenance "$@"
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "❌ Especifica una acción"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
