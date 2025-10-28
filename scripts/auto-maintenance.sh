#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CRON_LOG="$PROJECT_ROOT/data/logs/maintenance.log"

source "$SCRIPT_DIR/common/env-loader.sh"

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
  - Actualización DNS cada 30 minutos
  - Verificación de servicios cada 5 minutos
  - Limpieza de logs semanalmente

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
        cron_log "❌ Error cargando configuración"
        return 1
    fi

    # Ejecutar actualización y capturar la salida
    local dns_output
    local dns_exit_code=0

    # Crear un archivo temporal para la salida del DNS
    local temp_log="/tmp/dns_update_$$.log"

    if dns_output=$("$SCRIPT_DIR/update-dns.sh" 2>&1); then
        dns_exit_code=0
    else
        dns_exit_code=$?
    fi

    # Agregar la salida del DNS al log (ya tiene formato consistente de timestamp)
    if [[ -n "$dns_output" ]]; then
        echo "$dns_output" >> "$CRON_LOG"
    fi

    # Evaluar el resultado
    if [[ $dns_exit_code -eq 0 ]]; then
        # Verificar si hubo cambios o no
        if echo "$dns_output" | grep -q "sin cambios"; then
            cron_log "✅ DNS verificado - sin cambios necesarios"
        elif echo "$dns_output" | grep -q "DNS actualizado correctamente"; then
            cron_log "✅ DNS actualizado correctamente"
        else
            cron_log "✅ DNS procesado exitosamente"
        fi
    else
        cron_log "❌ Error actualizando DNS (código: $dns_exit_code)"
        return 1
    fi

    rm -f "$temp_log" 2>/dev/null || true
}

# Verificar que los servicios estén corriendo
check_services() {
    cron_log "🔍 Verificando estado de servicios..."

    local services_down=()
    local docker_dirs=("$PROJECT_ROOT/docker"/*)

    for stack_dir in "${docker_dirs[@]}"; do
        if [[ -d "$stack_dir" && -f "$stack_dir/docker-compose.yml" ]]; then
            local stack_name="$(basename "$stack_dir")"

            cd "$stack_dir"
            local running_containers
            running_containers=$(docker-compose ps -q 2>/dev/null | wc -l)

            if [[ $running_containers -eq 0 ]]; then
                services_down+=("$stack_name")
                cron_log "⚠️ Stack $stack_name no está corriendo"
            else
                cron_log "✅ Stack $stack_name corriendo ($running_containers contenedores)"
            fi
        fi
    done

    if [[ ${#services_down[@]} -gt 0 ]]; then
        cron_log "❌ Servicios caídos detectados: ${services_down[*]}"

        # Opcional: intentar reinicios automáticos
        # for service in "${services_down[@]}"; do
        #     cron_log "🔄 Intentando reiniciar $service..."
        #     cd "$PROJECT_ROOT/docker/$service"
        #     docker-compose up -d >> "$CRON_LOG" 2>&1
        # done

        return 1
    else
        cron_log "✅ Todos los servicios están corriendo correctamente"
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
    local current_user="$(whoami)"

    cat << EOF
# Home Server - Automatización DNS y servicios
# Instalado: $(date)

# EJECUCIÓN AL INICIO DEL SISTEMA (recupera tareas perdidas)
@reboot sleep 60 && $SCRIPT_DIR/auto-maintenance.sh --startup >/dev/null 2>&1

# Actualizar DNS cada 30 minutos (solo si está encendido)
*/30 * * * * $SCRIPT_DIR/auto-maintenance.sh --dns-only >/dev/null 2>&1

# Verificar servicios cada 5 minutos
*/5 * * * * $SCRIPT_DIR/auto-maintenance.sh --check-only >/dev/null 2>&1

# Limpieza semanal (domingos a las 3:00 AM)
0 3 * * 0 $SCRIPT_DIR/auto-maintenance.sh --cleanup-only >/dev/null 2>&1

# Mantenimiento completo diario (2:00 AM) - usa anacron si está disponible
0 2 * * * $SCRIPT_DIR/auto-maintenance.sh --daily >/dev/null 2>&1

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
        log "   - DNS: cada 30 minutos"
        log "   - Servicios: cada 5 minutos"
        log "   - Limpieza: domingos 3:00 AM"
        log "   - Mantenimiento: diario 2:00 AM"

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
    local last_run_file="$PROJECT_ROOT/data/logs/last_run"
    local now=$(date +%s)
    local last_run=0

    # Leer último timestamp de ejecución
    if [[ -f "$last_run_file" ]]; then
        last_run=$(cat "$last_run_file" 2>/dev/null || echo 0)
    fi

    local hours_since=$((($now - $last_run) / 3600))

    cron_log "⏰ Tiempo desde última ejecución: ${hours_since} horas"

    # Si han pasado más de 2 horas, ejecutar tareas de recuperación
    if [[ $hours_since -gt 2 ]]; then
        cron_log "🔄 Ejecutando tareas de recuperación (PC estuvo apagado ${hours_since}h)"

        # Ejecutar DNS inmediatamente
        run_dns_update

        # Si han pasado más de 24 horas, ejecutar mantenimiento completo
        if [[ $hours_since -gt 24 ]]; then
            cron_log "📅 Ejecutando mantenimiento completo (>24h sin ejecutar)"
            cleanup_logs
        fi

        check_services
    else
        cron_log "✅ Sistema funcionando normalmente (última ejecución: ${hours_since}h)"
    fi

    # Actualizar timestamp
    echo "$now" > "$last_run_file"
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

# Mantenimiento diario con anacron-like behavior
run_daily() {
    local daily_marker="$PROJECT_ROOT/data/logs/daily_marker"
    local today=$(date +%Y%m%d)
    local last_daily=""

    if [[ -f "$daily_marker" ]]; then
        last_daily=$(cat "$daily_marker" 2>/dev/null || echo "")
    fi

    # Solo ejecutar si no se ha hecho hoy
    if [[ "$last_daily" != "$today" ]]; then
        setup_logs
        cron_log "📅 Ejecutando mantenimiento diario para $today"

        run_dns_update
        check_services
        cleanup_logs

        # Marcar como completado
        echo "$today" > "$daily_marker"
        cron_log "✅ Mantenimiento diario completado para $today"
    else
        # Solo actualizar timestamp para check_missed_tasks
        echo "$(date +%s)" > "$PROJECT_ROOT/data/logs/last_run"
    fi
}

# Ejecutar mantenimiento manual
run_maintenance() {
    local dns_only=false
    local check_only=false
    local cleanup_only=false
    local full=false
    local startup=false
    local daily=false

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
            --full)
                full=true
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
            *)
                shift
                ;;
        esac
    done

    if [[ "$startup" == "true" ]]; then
        run_startup
    elif [[ "$daily" == "true" ]]; then
        run_daily
    elif [[ "$dns_only" == "true" ]]; then
        setup_logs
        run_dns_update
        echo "$(date +%s)" > "$PROJECT_ROOT/data/logs/last_run"
    elif [[ "$check_only" == "true" ]]; then
        setup_logs
        check_services
        echo "$(date +%s)" > "$PROJECT_ROOT/data/logs/last_run"
    elif [[ "$cleanup_only" == "true" ]]; then
        setup_logs
        cleanup_logs
    else
        # Mantenimiento completo
        setup_logs
        cron_log "🚀 Iniciando mantenimiento completo..."
        run_dns_update
        check_services

        if [[ "$full" == "true" ]]; then
            cleanup_logs
        fi

        echo "$(date +%s)" > "$PROJECT_ROOT/data/logs/last_run"
        cron_log "✅ Mantenimiento completado"
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
        --dns-only|--check-only|--cleanup-only|--full|--startup|--daily)
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
