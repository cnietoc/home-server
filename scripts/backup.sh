#!/usr/bin/env bash

# Script para crear backups automáticos de stacks
# Utiliza la configuración definida en stacks.yml

set -euo pipefail

BACKUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_PROJECT_ROOT="$(dirname "$BACKUP_SCRIPT_DIR")"

# Cargar funciones de stack-info
source "$BACKUP_PROJECT_ROOT/scripts/stack-info.sh" || {
    echo "❌ Error: No se pudo cargar stack-info.sh" >&2
    exit 1
}

# Cargar env-loader
source "$BACKUP_PROJECT_ROOT/scripts/common/env-loader.sh" || {
    echo "❌ Error: No se pudo cargar env-loader.sh" >&2
    exit 1
}

# Variables globales
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_BASE_DIR="$BACKUP_PROJECT_ROOT/data/backups"
DATA_BASE_DIR="$BACKUP_PROJECT_ROOT/data"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    log "❌ $*" >&2
}

# Verificar que el directorio de backups está configurado
check_backup_directory() {
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        error "Directorio de backups no encontrado: $BACKUP_BASE_DIR"
        error "Configúralo con: ./scripts/link.sh backups /ruta/a/backups"
        return 1
    fi

    if [[ ! -w "$BACKUP_BASE_DIR" ]]; then
        error "No tienes permisos de escritura en: $BACKUP_BASE_DIR"
        return 1
    fi

    return 0
}

# Crear archivo .gitignore temporal para exclusiones
create_exclusion_file() {
    local stack_name="$1"
    local temp_file="$2"

    # Crear archivo temporal vacío
    > "$temp_file"

    # Obtener exclusiones del stack si existen
    local exclusions
    exclusions=$(get_backup_exclusions "$stack_name" 2>/dev/null || echo "")

    if [[ -n "$exclusions" ]]; then
        log "📋 Exclusiones para stack '$stack_name':"
        while IFS= read -r exclusion; do
            [[ -z "$exclusion" ]] && continue
            echo "$exclusion" >> "$temp_file"
            log "   - $exclusion"
        done <<< "$exclusions"
    else
        log "📋 Sin exclusiones específicas para stack '$stack_name'"
    fi

    # Siempre excluir ciertos archivos/directorios comunes
    cat >> "$temp_file" << 'EOF'
# Exclusiones automáticas del sistema de backup
*.tmp
*.temp
.DS_Store
Thumbs.db
*.log
.git/
node_modules/
EOF

    log "📁 Archivo de exclusiones creado: $temp_file"
}

# Crear backup de un stack específico
backup_stack() {
    local stack_name="$1"

    log "🔄 Iniciando backup del stack: $stack_name"

    local stack_data_dir="$DATA_BASE_DIR/$stack_name"

    # Verificar que existe el directorio del stack
    if [[ ! -d "$stack_data_dir" ]]; then
        log "ℹ️ Directorio del stack no existe, creando backup vacío: $stack_data_dir"
        # Crear backup vacío para mantener consistencia
        local backup_file="$BACKUP_BASE_DIR/${stack_name}-${BACKUP_DATE}.tar.gz"
        tar -czf "$backup_file" --files-from /dev/null
        log "✅ Backup vacío creado: $(basename "$backup_file")"
        return 0
    fi

    # Crear archivo temporal de exclusiones
    local exclusion_file=$(mktemp)
    trap "rm -f '$exclusion_file'" EXIT

    create_exclusion_file "$stack_name" "$exclusion_file"

    # Nombre del archivo de backup
    local backup_file="$BACKUP_BASE_DIR/${stack_name}-${BACKUP_DATE}.tar.gz"

    log "📦 Creando backup: $(basename "$backup_file")"
    log "📁 Directorio origen: $stack_data_dir"

    # Crear backup usando tar con exclusiones estilo gitignore
    # Usamos --exclude-from pero procesamos el archivo para convertir patrones gitignore a tar
    local tar_exclude_file=$(mktemp)
    trap "rm -f '$exclusion_file' '$tar_exclude_file'" EXIT

    # Convertir patrones gitignore a formato tar
    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue

        # Convertir patrones globstar (**) a formato tar
        if [[ "$pattern" =~ \*\* ]]; then
            # Patrón con ** - convertir a múltiples exclusiones
            pattern="${pattern//\*\*\/*/}"
            pattern="${pattern//\*\*/}"
            echo "$pattern" >> "$tar_exclude_file"
            echo "*/$pattern" >> "$tar_exclude_file"
            echo "*/*/$pattern" >> "$tar_exclude_file"
        else
            echo "$pattern" >> "$tar_exclude_file"
        fi
    done < "$exclusion_file"

    # Crear el backup
    local files_backed_up=0
    local backup_size=0

    if tar -czf "$backup_file" \
        --exclude-from="$tar_exclude_file" \
        -C "$DATA_BASE_DIR" \
        "$stack_name" 2>/dev/null; then

        # Obtener estadísticas del backup
        backup_size=$(du -h "$backup_file" | cut -f1)
        files_backed_up=$(tar -tzf "$backup_file" 2>/dev/null | wc -l)

        log "✅ Backup completado: $(basename "$backup_file")"
        log "📊 Tamaño: $backup_size"
        log "📄 Archivos incluidos: $files_backed_up"
    else
        error "Falló la creación del backup para: $stack_name"
        rm -f "$backup_file"  # Limpiar archivo parcial
        return 1
    fi

    # Limpiar archivos temporales
    rm -f "$exclusion_file" "$tar_exclude_file"
    trap - EXIT

    return 0
}

# Mostrar resumen de backup
show_backup_summary() {
    local start_time="$1"
    local end_time="$(date +%s)"
    local duration=$((end_time - start_time))

    log "📊 Resumen del backup:"
    log "⏱️ Duración: ${duration}s"
    log "📁 Backups creados en: $BACKUP_BASE_DIR"

    # Mostrar archivos de backup creados hoy
    local today=$(date +%Y%m%d)
    local backup_files
    backup_files=$(find "$BACKUP_BASE_DIR" -name "*-${today}-*.tar.gz" -type f 2>/dev/null || true)

    if [[ -n "$backup_files" ]]; then
        log "📦 Archivos de backup de hoy:"
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local size=$(du -h "$file" | cut -f1)
            log "   - $(basename "$file") ($size)"
        done <<< "$backup_files"

        # Tamaño total
        local total_size
        total_size=$(echo "$backup_files" | xargs du -ch 2>/dev/null | tail -1 | cut -f1)
        log "💾 Tamaño total de backups de hoy: $total_size"
    fi
}

# Función principal
main() {
    local stacks_to_backup=()
    local backup_all=false

    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all|-a)
                backup_all=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                stacks_to_backup+=("$1")
                shift
                ;;
        esac
    done

    # Inicializar stack-info
    if ! init_stack_info; then
        error "No se pudo inicializar stack-info"
        exit 1
    fi

    # Verificar directorio de backups
    if ! check_backup_directory; then
        exit 1
    fi

    local start_time=$(date +%s)
    log "🚀 Iniciando proceso de backup ($(date))"

    # Determinar qué stacks respaldar
    if [[ "$backup_all" == "true" ]]; then
        # Respaldar todos los stacks disponibles
        local all_stacks
        all_stacks=$(get_available_stacks)
        while IFS= read -r stack; do
            [[ -z "$stack" ]] && continue
            stacks_to_backup+=("$stack")
        done <<< "$all_stacks"
    fi

    # Si no se especificaron stacks, mostrar ayuda
    if [[ ${#stacks_to_backup[@]} -eq 0 ]]; then
        error "No se especificaron stacks para backup"
        echo ""
        show_help
        exit 1
    fi

    log "📦 Stacks a respaldar: ${stacks_to_backup[*]}"

    # Crear directorio de backup si no existe
    mkdir -p "$BACKUP_BASE_DIR"

    # Procesar cada stack
    local successful_backups=0
    local failed_backups=0

    for stack in "${stacks_to_backup[@]}"; do
        if backup_stack "$stack"; then
            ((successful_backups++))
        else
            ((failed_backups++))
        fi
        echo ""  # Separador entre stacks
    done

    # Mostrar resumen
    log "✅ Backups exitosos: $successful_backups"
    if [[ $failed_backups -gt 0 ]]; then
        log "❌ Backups fallidos: $failed_backups"
    fi

    show_backup_summary "$start_time"
    log "🎉 Proceso de backup completado"

    # Código de salida basado en resultados
    if [[ $failed_backups -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $0 [opciones] [stack1] [stack2] ...

DESCRIPCIÓN:
  Crea backups de los stacks especificados según la configuración en stacks.yml.
  Cada backup incluye todo el contenido de data/{stack} excluyendo archivos/
  directorios especificados en la configuración de exclusiones.

OPCIONES:
  --all, -a     Respaldar todos los stacks disponibles
  --help, -h    Mostrar esta ayuda

ARGUMENTOS:
  stack1, stack2, ...  Nombres de stacks específicos a respaldar

EJEMPLOS:
  $0 media                    # Backup solo del stack media
  $0 platform home            # Backup de platform y home
  $0 --all                    # Backup de todos los stacks

CONFIGURACIÓN:
  Los backups se configuran en stacks.yml:

  stacks:
    mi_stack:
      backups:
        exclude:
          - library         # Excluir directorio específico
          - downloads       # Excluir otro directorio
          - "**/*.zip"      # Excluir archivos ZIP recursivamente

UBICACIÓN DE BACKUPS:
  $BACKUP_BASE_DIR

FORMATO DE ARCHIVOS:
  {stack_name}-{YYYYMMDD-HHMMSS}.tar.gz

NOTAS:
  - Si un stack no tiene configuración de backup, se respaldará todo su contenido
  - Los patrones de exclusión siguen el formato gitignore
  - Se excluyen automáticamente: *.tmp, *.log, .DS_Store, node_modules/, etc.
  - El directorio de backups debe estar configurado previamente con link.sh
EOF
}

# Ejecutar función principal si el script se ejecuta directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
