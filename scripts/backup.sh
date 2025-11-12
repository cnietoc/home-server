#!/usr/bin/env bash

# Script para crear backups automáticos de stacks
# Utiliza la configuración definida en stacks.yml

set -uo pipefail  # Removido -e para manejar errores manualmente

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
        log "ℹ️ Directorio del stack no existe, saltando: $stack_data_dir"
        return 0
    fi

    # Verificar si el directorio tiene contenido (excluyendo archivos ocultos)
    if [[ -z "$(find "$stack_data_dir" -type f 2>/dev/null | head -1)" ]]; then
        log "ℹ️ Directorio del stack está vacío, saltando: $stack_data_dir"
        return 0
    fi

    # Crear archivo temporal de exclusiones
    local exclusion_file=$(mktemp)
    local tar_exclude_file=$(mktemp)

    create_exclusion_file "$stack_name" "$exclusion_file"

    # Nombre del archivo de backup
    local backup_file="$BACKUP_BASE_DIR/${stack_name}-${BACKUP_DATE}.tar.gz"

    log "📦 Creando backup: $(basename "$backup_file")"
    log "📁 Directorio origen: $stack_data_dir"

    # Convertir patrones gitignore a formato tar
    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue

        # Convertir patrones globstar (**) a formato tar
        if [[ "$pattern" =~ \*\* ]]; then
            # Patrón con ** - convertir a múltiples exclusiones
            local clean_pattern="${pattern//\*\*\/*/}"
            clean_pattern="${clean_pattern//\*\*/}"
            echo "$clean_pattern" >> "$tar_exclude_file"
            echo "*/$clean_pattern" >> "$tar_exclude_file"
            echo "*/*/$clean_pattern" >> "$tar_exclude_file"
        else
            echo "$pattern" >> "$tar_exclude_file"
        fi
    done < "$exclusion_file"

    # Crear el backup
    local files_backed_up=0
    local backup_size=0
    local backup_created=false
    local result=0

    # Crear backup temporal primero
    local temp_backup_file="${backup_file}.tmp"
    local tar_output_file=$(mktemp)
    local files_to_backup=$(mktemp)

    log "📄 Comprimiendo archivos..."

    # Crear lista de archivos a incluir (solo archivos, no directorios)
    (cd "$DATA_BASE_DIR" && find "$stack_name" -type f -print 2>/dev/null) | while IFS= read -r file; do
        local should_exclude=false

        # Verificar contra cada patrón de exclusión (usar el archivo original, no el procesado)
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue

            # Convertir patrón gitignore a bash pattern
            if [[ "$pattern" =~ ^\*\*/\*\. ]]; then
                # Patrones como **/*.zip, **/*.log, etc.
                local extension="${pattern##**/}"  # Obtiene "*.zip", "*.log", etc.
                if [[ "$file" == $extension ]]; then
                    should_exclude=true
                    break
                fi
            elif [[ "$pattern" =~ \*\*/ ]]; then
                # Patrón **/ - coincide con cualquier directorio
                local bash_pattern="${pattern//\*\*\//}"
                if [[ "$file" == *"$bash_pattern" ]]; then
                    should_exclude=true
                    break
                fi
            elif [[ "$pattern" =~ /\*\* ]]; then
                # Patrón /** - coincide con cualquier cosa después de una ruta específica
                local bash_pattern="${pattern//\/\*\*/}"
                if [[ "$file" == "$bash_pattern"* ]]; then
                    should_exclude=true
                    break
                fi
            elif [[ "$pattern" =~ \*\*.*\* ]]; then
                # Patrones como **/*.zip - coinciden con archivos en cualquier subdirectorio
                local extension="${pattern##**/}"
                if [[ "$file" == *"$extension" ]]; then
                    should_exclude=true
                    break
                fi
            elif [[ "$pattern" =~ \*\* ]]; then
                # Otros patrones con ** - convertir a coincidencia parcial
                local bash_pattern="${pattern//\*\*/}"
                if [[ "$file" == *"$bash_pattern"* ]]; then
                    should_exclude=true
                    break
                fi
            else
                # Patrón normal - verificar si coincide exactamente o como substring
                if [[ "$file" == *"$pattern"* || "$file" == "$pattern" ]]; then
                    should_exclude=true
                    break
                fi
            fi
        done < "$exclusion_file"


        # Solo añadir si no está excluido
        if [[ "$should_exclude" == "false" ]]; then
            echo "$file"
        fi
    done > "$files_to_backup"

    # Verificar si hay archivos para respaldar
    if [[ ! -s "$files_to_backup" ]]; then
        log "ℹ️ No hay archivos para respaldar después de aplicar exclusiones, saltando"
        rm -f "$temp_backup_file" "$tar_output_file" "$files_to_backup"
        rm -f "$exclusion_file" "$tar_exclude_file"
        return 0
    fi

    # Crear backup usando la lista de archivos filtrada
    if (cd "$DATA_BASE_DIR" && tar -czf "$temp_backup_file" -T "$files_to_backup") 2>"$tar_output_file"; then

        # Mostrar archivos que se están incluyendo en el backup
        if [[ -s "$files_to_backup" ]]; then
            local file_count=0
            log "📄 Archivos incluidos en el backup:"
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                # Mostrar path relativo al stack (quitar el prefijo del stack)
                local relative_path="${file#$stack_name/}"

                # Obtener información adicional del archivo
                local full_path="$DATA_BASE_DIR/$file"
                if [[ -f "$full_path" ]]; then
                    local file_size=$(du -h "$full_path" 2>/dev/null | cut -f1 || echo "?")
                    local file_modified=$(stat -c %Y "$full_path" 2>/dev/null || stat -f %m "$full_path" 2>/dev/null || echo "0")
                    local file_date=$(date -d "@$file_modified" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "$file_modified" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")

                    printf "   📄 %-60s %8s %s\n" "$relative_path" "$file_size" "$file_date"
                else
                    printf "   📄 %s\n" "$relative_path"
                fi
                file_count=$((file_count + 1))
            done < "$files_to_backup"

            # Mostrar resumen por tipo de archivo
            if [[ $file_count -gt 0 ]]; then
                log "📊 Resumen por tipo de archivo:"
                local extensions_summary=$(cat "$files_to_backup" | grep -E '\.[^/]*$' | sed 's/.*\.//' | sort | uniq -c | sort -nr)
                if [[ -n "$extensions_summary" ]]; then
                    while IFS= read -r count ext; do
                        [[ -z "$count" || -z "$ext" ]] && continue
                        printf "   📋 %-10s: %3d archivos\n" "$ext" "$count"
                    done <<< "$extensions_summary"
                else
                    log "   📋 Sin archivos con extensión detectados"
                fi
            else
                log "   ℹ️ No se encontraron archivos para procesar"
            fi
        fi
                fi
            else
                log "   ℹ️ No se encontraron archivos para procesar"
            fi
        fi

        # Verificar si el backup contiene archivos
        files_backed_up=$(tar -tzf "$temp_backup_file" 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$files_backed_up" -gt 0 ]]; then
            # Mover backup temporal al nombre final
            mv "$temp_backup_file" "$backup_file"
            backup_created=true

            # Obtener estadísticas del backup
            backup_size=$(du -h "$backup_file" | cut -f1)

            log "✅ Backup completado: $(basename "$backup_file")"
            log "📊 Tamaño: $backup_size"
            log "📄 Archivos incluidos: $files_backed_up"
        else
            log "ℹ️ No hay archivos para respaldar después de aplicar exclusiones, saltando"
            rm -f "$temp_backup_file"
        fi
    else
        error "Falló la creación del backup para: $stack_name"
        # Mostrar error de tar si está disponible
        if [[ -s "$tar_output_file" ]]; then
            error "Salida de tar:"
            cat "$tar_output_file" >&2
        fi
        rm -f "$temp_backup_file"
        result=1
    fi

    # Limpiar archivos temporales
    rm -f "$exclusion_file" "$tar_exclude_file" "$tar_output_file" "$files_to_backup"

    return $result
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
    local skipped_backups=0

    for stack in "${stacks_to_backup[@]}"; do
        log "────────────────────────────────────────"

        # Verificar que el stack existe
        if ! stack_exists "$stack"; then
            log "⚠️ Stack '$stack' no existe en la configuración, saltando"
            skipped_backups=$((skipped_backups + 1))
            continue
        fi

        # Ejecutar backup con manejo de errores
        if backup_stack "$stack"; then
            successful_backups=$((successful_backups + 1))
        else
            failed_backups=$((failed_backups + 1))
        fi
    done


    # Mostrar resumen
    log "────────────────────────────────────────"
    log "✅ Backups exitosos: $successful_backups"
    if [[ $skipped_backups -gt 0 ]]; then
        log "⏭️ Backups saltados: $skipped_backups"
    fi
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
