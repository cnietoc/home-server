#!/usr/bin/env bash

# Script para crear backups automáticos de stacks
# Utiliza la configuración definida en stacks.yml

set -uo pipefail  # Removido -e para manejar errores manualmente

BACKUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_PROJECT_ROOT="$(dirname "$BACKUP_SCRIPT_DIR")"
STACK_INFO_SCRIPT="$BACKUP_SCRIPT_DIR/stack-info.sh"

# Cargar funciones de stack-info
source "$STACK_INFO_SCRIPT" || {
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
DOCKER_DIR="$BACKUP_PROJECT_ROOT/docker"
SAFE_MODE=false
CLEANUP_MODE=false
KEEP_BACKUPS=5
VERBOSE_MODE=false
RESTORE_MODE=false
RESTORE_BACKUP=""
RESTORE_STACK=""

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    log "❌ $*" >&2
}

# Listar backups disponibles para un stack
list_backups() {
    local stack_name="$1"

    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        error "Directorio de backups no existe: $BACKUP_BASE_DIR"
        return 1
    fi

    local backups
    if [[ -n "$stack_name" ]]; then
        backups=$(find "$BACKUP_BASE_DIR" -name "${stack_name}-*.tar.gz" -type f 2>/dev/null | sort -r || true)
    else
        backups=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f 2>/dev/null | sort -r || true)
    fi

    if [[ -z "$backups" ]]; then
        if [[ -n "$stack_name" ]]; then
            log "ℹ️ No se encontraron backups para stack '$stack_name'"
        else
            log "ℹ️ No se encontraron backups"
        fi
        return 1
    fi

    echo "$backups"
}

# Mostrar menú de selección de backup usando fzf
select_backup() {
    local stack_name="$1"

    # Verificar que fzf esté instalado
    if ! command -v fzf >/dev/null 2>&1; then
        error "fzf no está instalado. Instálalo con:"
        error "  - Ubuntu/Debian: sudo apt install fzf"
        error "  - macOS: brew install fzf"
        error "  - Fedora/RHEL: sudo dnf install fzf"
        return 1
    fi

    log "📦 Buscando backups disponibles..."

    local backups
    backups=$(list_backups "$stack_name")

    if [[ -z "$backups" ]]; then
        return 1
    fi

    # Crear lista formateada para fzf con información adicional
    local formatted_list=""
    while IFS= read -r backup; do
        [[ -z "$backup" ]] && continue

        local basename_backup=$(basename "$backup")
        local backup_size=$(du -h "$backup" 2>/dev/null | cut -f1 || echo "?")
        local backup_date=$(stat -c %y "$backup" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup" 2>/dev/null || echo "unknown")

        # Formato: ruta_completa|nombre|tamaño|fecha
        formatted_list+="$(printf "%s|%-60s %10s  %s\n" "$backup" "$basename_backup" "$backup_size" "$backup_date")"$'\n'
    done <<< "$backups"

    if [[ -z "$formatted_list" ]]; then
        error "No se encontraron backups"
        return 1
    fi

    # Usar fzf para seleccionar
    local selected
    selected=$(echo "$formatted_list" | fzf \
        --height=50% \
        --reverse \
        --border \
        --prompt="Selecciona un backup > " \
        --header="$(printf '%-60s %10s  %s' 'ARCHIVO' 'TAMAÑO' 'FECHA')" \
        --delimiter='|' \
        --with-nth=2 \
        --preview='echo "📦 Backup: {2}" && echo "" && echo "📊 Información:" && tar -tzf {1} 2>/dev/null | head -20 && echo "..." && echo "" && echo "📄 Total de archivos: $(tar -tzf {1} 2>/dev/null | wc -l)"' \
        --preview-window=right:50%:wrap \
    )

    if [[ -z "$selected" ]]; then
        log "❌ Operación cancelada"
        return 1
    fi

    # Extraer la ruta completa del backup seleccionado
    local selected_backup=$(echo "$selected" | cut -d'|' -f1)
    echo "$selected_backup"
    return 0
}

# Extraer nombre del stack desde el nombre del backup
extract_stack_from_backup() {
    local backup_file="$1"
    local basename_backup=$(basename "$backup_file")

    # Formato: {stack_name}-{YYYYMMDD-HHMMSS}.tar.gz
    # Extraer todo hasta el primer guion seguido de una fecha
    local stack_name="${basename_backup%-[0-9]*}"

    echo "$stack_name"
}

# Restaurar backup
restore_backup() {
    local backup_file="$1"
    local target_stack="$2"
    local services_were_running=false
    local services_stopped_successfully=false

    if [[ ! -f "$backup_file" ]]; then
        error "Archivo de backup no existe: $backup_file"
        return 1
    fi

    # Si no se especifica stack destino, extraerlo del nombre del backup
    if [[ -z "$target_stack" ]]; then
        target_stack=$(extract_stack_from_backup "$backup_file")
    fi

    log "🔄 Iniciando restore del backup: $(basename "$backup_file")"
    log "📦 Stack destino: $target_stack"

    # Verificar que el stack existe
    if ! stack_exists "$target_stack"; then
        error "Stack '$target_stack' no existe en la configuración"
        return 1
    fi

    local stack_data_dir="$DATA_BASE_DIR/$target_stack"

    # Confirmar sobrescritura si el directorio existe y tiene contenido
    if [[ -d "$stack_data_dir" ]]; then
        local file_count=$(find "$stack_data_dir" -type f 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$file_count" -gt 0 ]]; then
            log "⚠️ ADVERTENCIA: El directorio '$stack_data_dir' contiene $file_count archivos"
            log "⚠️ Esta operación SOBRESCRIBIRÁ los datos existentes"
            echo ""
            read -p "¿Estás seguro de continuar? (escribe 'SI' para confirmar): " confirmation

            if [[ "$confirmation" != "SI" ]]; then
                log "❌ Operación cancelada"
                return 1
            fi
        fi
    fi

    # Detener servicios si están ejecutándose
    if check_stack_services "$target_stack"; then
        services_were_running=true
        log "🔍 Servicios detectados para stack '$target_stack'"

        if stop_stack_services "$target_stack"; then
            services_stopped_successfully=true
            log "⏳ Esperando 5 segundos para que se liberen los archivos..."
            sleep 5
        else
            error "⚠️ No se pudieron detener los servicios"
            read -p "¿Continuar de todos modos? (escribe 'SI' para confirmar): " confirmation

            if [[ "$confirmation" != "SI" ]]; then
                log "❌ Operación cancelada"
                return 1
            fi
        fi
    fi

    # Crear backup del estado actual antes de restaurar (respetando exclusiones)
    if [[ -d "$stack_data_dir" ]] && [[ -n "$(find "$stack_data_dir" -type f 2>/dev/null | head -1)" ]]; then
        log "💾 Creando backup del estado actual antes de restaurar..."
        local safety_backup="$BACKUP_BASE_DIR/${target_stack}-pre-restore-${BACKUP_DATE}.tar.gz"

        # Crear backup de seguridad usando la misma lógica que backup_stack
        # para respetar las exclusiones configuradas
        local exclusion_file=$(mktemp)
        local tar_exclude_file=$(mktemp)

        create_exclusion_file "$target_stack" "$exclusion_file"

        # Convertir patrones gitignore a formato tar
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue

            # Eliminar espacios en blanco al inicio/final
            pattern=$(echo "$pattern" | xargs)

            # Convertir patrón gitignore a patrón tar --exclude
            if [[ "$pattern" == /* ]]; then
                # Patrón absoluto desde la raíz del stack
                echo "${target_stack}${pattern}" >> "$tar_exclude_file"
            elif [[ "$pattern" == */* ]]; then
                # Patrón con ruta
                echo "${target_stack}/${pattern}" >> "$tar_exclude_file"
            else
                # Patrón simple (nombre de archivo/directorio)
                echo "${target_stack}/${pattern}" >> "$tar_exclude_file"
            fi
        done < "$exclusion_file"

        # Crear backup de seguridad con exclusiones
        if (cd "$DATA_BASE_DIR" && tar -czf "$safety_backup" --exclude-from="$tar_exclude_file" "$target_stack" 2>/dev/null); then
            local safety_size=$(du -h "$safety_backup" 2>/dev/null | cut -f1 || echo "?")
            log "✅ Backup de seguridad creado: $(basename "$safety_backup") ($safety_size)"
        else
            log "⚠️ No se pudo crear backup de seguridad del estado actual"
            read -p "¿Continuar de todos modos? (escribe 'SI' para confirmar): " confirmation

            if [[ "$confirmation" != "SI" ]]; then
                log "❌ Operación cancelada"
                rm -f "$exclusion_file" "$tar_exclude_file"
                # Reiniciar servicios si los detuvimos
                if [[ "$services_stopped_successfully" == "true" ]]; then
                    start_stack_services "$target_stack"
                fi
                return 1
            fi
        fi

        rm -f "$exclusion_file" "$tar_exclude_file"
    fi

    # NO eliminamos el contenido actual - solo extraemos el backup
    # Esto sobrescribirá archivos existentes pero mantendrá archivos que
    # no están en el backup (ej: archivos en directorios excluidos)
    if [[ ! -d "$stack_data_dir" ]]; then
        log "📁 Creando directorio para stack '$target_stack'..."
        mkdir -p "$stack_data_dir"
    fi

    # Restaurar backup
    log "📦 Restaurando backup..."
    log "📁 Destino: $stack_data_dir"
    log "ℹ️ Los archivos del backup sobrescribirán los existentes"

    # Extraer y contar archivos
    local temp_list=$(mktemp)
    if tar -tzf "$backup_file" > "$temp_list" 2>/dev/null; then
        local file_count=$(wc -l < "$temp_list" | tr -d ' ')
        log "📄 Archivos a restaurar: $file_count"

        if [[ "$VERBOSE_MODE" == "true" ]]; then
            log "📋 Lista de archivos:"
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                echo "   📄 $file"
            done < "$temp_list"
        fi

        rm -f "$temp_list"
    fi

    # Extraer backup (sobrescribe pero no elimina otros archivos)
    if (cd "$DATA_BASE_DIR" && tar -xzf "$backup_file"); then
        local restored_size=$(du -sh "$stack_data_dir" 2>/dev/null | cut -f1 || echo "?")
        log "✅ Backup restaurado exitosamente"
        log "📊 Tamaño total del stack: $restored_size"

        # Verificar archivos restaurados
        local restored_files=$(find "$stack_data_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
        log "📄 Total de archivos en el stack: $restored_files"
    else
        error "❌ Error al restaurar backup"
        rm -f "$temp_list"
        # Reiniciar servicios si los detuvimos
        if [[ "$services_stopped_successfully" == "true" ]]; then
            start_stack_services "$target_stack"
        fi
        return 1
    fi

    # Reiniciar servicios si fueron detenidos
    if [[ "$services_stopped_successfully" == "true" ]]; then
        log "🔄 Reiniciando servicios del stack: $target_stack"
        if ! start_stack_services "$target_stack"; then
            error "❌ Error: No se pudieron reiniciar los servicios del stack '$target_stack'"
            error "⚠️ Los servicios permanecen detenidos. Reinícialos manualmente con:"
            error "   cd $DOCKER_DIR/$target_stack && docker compose up -d"
            return 1
        fi
    fi

    log "🎉 Restore completado exitosamente"
    return 0
}

# Limpiar backups antiguos manteniendo solo los más recientes
cleanup_old_backups() {
    local keep_count="$1"

    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log "⚠️ Directorio de backups no existe: $BACKUP_BASE_DIR"
        return 1
    fi

    log "🧹 Limpiando backups antiguos (manteniendo $keep_count más recientes por stack)..."

    # Obtener todos los stacks disponibles para limpiar
    local all_stacks
    all_stacks=$(get_available_stacks)

    local total_deleted=0
    local total_size_freed=0

    while IFS= read -r stack; do
        [[ -z "$stack" ]] && continue

        log "📁 Procesando stack: $stack"

        # Buscar backups de este stack específico
        local stack_backups
        stack_backups=$(find "$BACKUP_BASE_DIR" -name "${stack}-*.tar.gz" -type f 2>/dev/null || true)

        if [[ -z "$stack_backups" ]]; then
            log "   ℹ️ No se encontraron backups para stack '$stack'"
            continue
        fi

        # Contar backups existentes
        local backup_count=$(echo "$stack_backups" | wc -l)
        log "   📊 Encontrados $backup_count backups para stack '$stack'"

        if [[ $backup_count -le $keep_count ]]; then
            log "   ✅ Se mantienen todos los backups (≤ $keep_count)"
            continue
        fi

        # Ordenar por fecha de modificación (más recientes primero) y obtener los que hay que eliminar
        local to_delete_count=$((backup_count - keep_count))
        local files_to_delete
        files_to_delete=$(echo "$stack_backups" | xargs ls -t | tail -n "$to_delete_count")

        log "   🗑️ Eliminando $to_delete_count backups antiguos:"

        while IFS= read -r file_to_delete; do
            [[ -z "$file_to_delete" ]] && continue

            # Obtener tamaño del archivo antes de borrarlo
            local file_size=$(du -h "$file_to_delete" | cut -f1)
            local file_size_bytes=$(du -b "$file_to_delete" | cut -f1 2>/dev/null || stat -c%s "$file_to_delete" 2>/dev/null || echo "0")

            log "      - $(basename "$file_to_delete") ($file_size)"

            if rm -f "$file_to_delete"; then
                total_deleted=$((total_deleted + 1))
                total_size_freed=$((total_size_freed + file_size_bytes))
            else
                error "      ❌ Error al eliminar: $(basename "$file_to_delete")"
            fi
        done <<< "$files_to_delete"

        # Mostrar backups restantes
        local remaining_backups
        remaining_backups=$(find "$BACKUP_BASE_DIR" -name "${stack}-*.tar.gz" -type f | wc -l)
        log "   ✅ Quedan $remaining_backups backups para stack '$stack'"

    done <<< "$all_stacks"

    # Mostrar resumen de limpieza
    if [[ $total_deleted -gt 0 ]]; then
        local freed_size_readable=$(numfmt --to=iec-i --suffix=B "$total_size_freed" 2>/dev/null || echo "${total_size_freed}B")
        log "🎉 Limpieza completada:"
        log "   📁 Archivos eliminados: $total_deleted"
        log "   💾 Espacio liberado: $freed_size_readable"
    else
        log "✅ No hay backups antiguos que eliminar"
    fi

    return 0
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

# Parar servicios de un stack
stop_stack_services() {
    local stack_name="$1"
    local stack_docker_dir="$DOCKER_DIR/$stack_name"

    if [[ ! -d "$stack_docker_dir" ]]; then
        log "⚠️ Directorio Docker no encontrado para stack '$stack_name': $stack_docker_dir"
        return 1
    fi

    if [[ ! -f "$stack_docker_dir/docker-compose.yml" ]]; then
        log "⚠️ docker-compose.yml no encontrado para stack '$stack_name'"
        return 1
    fi

    log "🛑 Deteniendo servicios del stack: $stack_name"
    if (cd "$stack_docker_dir" && docker compose down); then
        log "✅ Servicios detenidos correctamente"
        return 0
    else
        log "❌ Error al detener servicios del stack '$stack_name'"
        return 1
    fi
}

# Levantar servicios de un stack
start_stack_services() {
    local stack_name="$1"
    local stack_docker_dir="$DOCKER_DIR/$stack_name"

    if [[ ! -d "$stack_docker_dir" ]]; then
        log "⚠️ Directorio Docker no encontrado para stack '$stack_name': $stack_docker_dir"
        return 1
    fi

    if [[ ! -f "$stack_docker_dir/docker-compose.yml" ]]; then
        log "⚠️ docker-compose.yml no encontrado para stack '$stack_name'"
        return 1
    fi

    log "🚀 Iniciando servicios del stack: $stack_name"
    if (cd "$stack_docker_dir" && docker compose up -d); then
        log "✅ Servicios iniciados correctamente"
        return 0
    else
        log "❌ Error al iniciar servicios del stack '$stack_name'"
        return 1
    fi
}

# Verificar que un stack existe en la configuración
stack_exists() {
    local stack_name="$1"

    # Usar stack-info para verificar si el stack existe
    "$STACK_INFO_SCRIPT" stack_exists "$stack_name" 2>/dev/null
    return $?
}

# Verificar si un stack tiene servicios Docker ejecutándose
check_stack_services() {
    local stack_name="$1"
    local stack_docker_dir="$DOCKER_DIR/$stack_name"

    if [[ ! -d "$stack_docker_dir" ]]; then
        return 1  # No tiene servicios Docker
    fi

    if [[ ! -f "$stack_docker_dir/docker-compose.yml" ]]; then
        return 1
    fi

    # Verificar si hay contenedores ejecutándose para este stack
    local running_containers
    running_containers=$(cd "$stack_docker_dir" && docker compose ps -q 2>/dev/null | wc -l)


    [[ "$running_containers" -gt 0 ]]
}
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
    local services_were_running=false
    local services_stopped_successfully=false

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

    # EN MODO SAFE, DETENER SERVICIOS ANTES DE GENERAR LA LISTA DE ARCHIVOS
    if [[ "$SAFE_MODE" == "true" ]]; then
        if check_stack_services "$stack_name"; then
            services_were_running=true
            log "🔍 Servicios detectados para stack '$stack_name'"

            if stop_stack_services "$stack_name"; then
                services_stopped_successfully=true
                # Esperar un momento para que los archivos se liberen y se estabilicen
                log "⏳ Esperando 5 segundos para que se liberen los archivos..."
                sleep 5
            else
                log "⚠️ No se pudieron detener los servicios, continuando con backup (archivos pueden estar en uso)"
            fi
        else
            log "ℹ️ No se detectaron servicios ejecutándose para stack '$stack_name'"
        fi
    fi

    # Crear el backup
    local files_backed_up=0
    local backup_size=0
    local backup_created=false
    local result=0

    # Crear backup temporal primero
    local temp_backup_file="${backup_file}.tmp"
    local tar_output_file=$(mktemp)
    local files_to_backup=$(mktemp)

    # Crear lista de archivos a incluir usando un enfoque más eficiente
    # Primero crear lista de todos los archivos
    local temp_all_files=$(mktemp)
    (cd "$DATA_BASE_DIR" && find "$stack_name" -type f -print 2>/dev/null) > "$temp_all_files"

    # Luego filtrar las exclusiones sin subshell
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local should_exclude=false

        # Verificar contra cada patrón de exclusión
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
            echo "$file" >> "$files_to_backup"
        fi
    done < "$temp_all_files"

    # Limpiar archivo temporal
    rm -f "$temp_all_files"

    # Verificar si hay archivos para respaldar
    if [[ ! -s "$files_to_backup" ]]; then
        log "ℹ️ No hay archivos para respaldar después de aplicar exclusiones, saltando"
        rm -f "$temp_backup_file" "$tar_output_file" "$files_to_backup"
        rm -f "$exclusion_file" "$tar_exclude_file"

        # En modo safe, si habíamos parado servicios, reiniciarlos antes de salir
        if [[ "$SAFE_MODE" == "true" && "$services_were_running" == "true" && "$services_stopped_successfully" == "true" ]]; then
            log "🔄 Reiniciando servicios tras cancelar backup sin archivos"
            start_stack_services "$stack_name"
        fi

        return 0
    fi

    # Continuar con el backup...

    # Mostrar archivos que se van a incluir en el backup y generar resumen
    local file_count=0
    local temp_file_sizes=$(mktemp)

    # Solo mostrar lista detallada si verbose está activado
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        log "📄 Archivos incluidos en el backup:"
    else
        log "📄 Procesando archivos para backup..."
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        # Mostrar path relativo al stack (quitar el prefijo del stack)
        local relative_path="${file#$stack_name/}"

        # Obtener información adicional del archivo
        local full_path="$DATA_BASE_DIR/$file"
        if [[ -f "$full_path" ]]; then
            local file_size=$(du -h "$full_path" 2>/dev/null | cut -f1 || echo "?")
            local file_size_bytes=$(du -b "$full_path" 2>/dev/null | cut -f1 || stat -c%s "$full_path" 2>/dev/null || echo "0")
            local file_modified=$(stat -c %Y "$full_path" 2>/dev/null || stat -f %m "$full_path" 2>/dev/null || echo "0")
            local file_date=$(date -d "@$file_modified" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "$file_modified" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")

            # Guardar información para análisis posterior: tamaño_bytes|path_relativo|extensión
            local basename_file=$(basename "$file")
            local ext=""
            if [[ "$basename_file" == *.* ]]; then
                ext="${basename_file##*.}"
            else
                ext="SIN_EXTENSION"
            fi
            echo "$file_size_bytes|$relative_path|$ext" >> "$temp_file_sizes"

            # Solo mostrar detalles de archivos si verbose está activado
            if [[ "$VERBOSE_MODE" == "true" ]]; then
                printf "   📄 %-60s %8s %s\n" "$relative_path" "$file_size" "$file_date"
            fi
        else
            if [[ "$VERBOSE_MODE" == "true" ]]; then
                printf "   📄 %s\n" "$relative_path"
            fi
        fi
        file_count=$((file_count + 1))
    done < "$files_to_backup"

    # Mostrar resumen por tipo de archivo con tamaños
    if [[ $file_count -gt 0 ]]; then
        log "📊 Resumen por tipo de archivo:"

        # Usar arrays asociativos para contar archivos y sumar tamaños
        declare -A ext_count ext_size_total

        while IFS='|' read -r size_bytes relative_path ext; do
            [[ -z "$size_bytes" || -z "$ext" ]] && continue
            ext_count["$ext"]=$((${ext_count["$ext"]:-0} + 1))
            ext_size_total["$ext"]=$((${ext_size_total["$ext"]:-0} + size_bytes))
        done < "$temp_file_sizes"

        # Crear archivo temporal para ordenar por cantidad de archivos
        local temp_ext_summary=$(mktemp)
        for ext in "${!ext_count[@]}"; do
            local readable_size=$(numfmt --to=iec-i --suffix=B ${ext_size_total["$ext"]} 2>/dev/null || echo "${ext_size_total["$ext"]}B")
            echo "${ext_count["$ext"]} $ext $readable_size" >> "$temp_ext_summary"
        done

        # Mostrar extensiones ordenadas por cantidad de archivos
        sort -nr "$temp_ext_summary" | while read -r count ext size_readable; do
            [[ -z "$count" || -z "$ext" ]] && continue
            if [[ "$ext" == "SIN_EXTENSION" ]]; then
                printf "   📋 %-15s: %3d archivos (%s)\n" "(sin ext)" "$count" "$size_readable"
            else
                printf "   📋 %-15s: %3d archivos (%s)\n" "$ext" "$count" "$size_readable"
            fi
        done

        # Mostrar top 5 de archivos más pesados
        log "🏆 Top 5 archivos más pesados:"
        sort -nr "$temp_file_sizes" | head -5 | while IFS='|' read -r size_bytes relative_path ext; do
            [[ -z "$size_bytes" || -z "$relative_path" ]] && continue
            local readable_size=$(numfmt --to=iec-i --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")
            printf "   🔸 %-8s %s\n" "$readable_size" "$relative_path"
        done

        # Limpiar archivos temporales
        rm -f "$temp_ext_summary"
    else
        log "   ℹ️ No se encontraron archivos para procesar"
    fi

    # Limpiar archivo temporal principal
    rm -f "$temp_file_sizes"

    log "📄 Comprimiendo archivos..."

    # Crear backup usando la lista de archivos filtrada
    if (cd "$DATA_BASE_DIR" && tar -czf "$temp_backup_file" -T "$files_to_backup") 2>"$tar_output_file"; then

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
    rm -f "$exclusion_file" "$tar_exclude_file" "$tar_output_file" "$files_to_backup" "$temp_all_files"

    # En modo safe, reiniciar servicios si fueron detenidos exitosamente
    if [[ "$SAFE_MODE" == "true" && "$services_were_running" == "true" && "$services_stopped_successfully" == "true" ]]; then
        log "🔄 Reiniciando servicios del stack: $stack_name"
        if ! start_stack_services "$stack_name"; then
            error "❌ Error crítico: No se pudieron reiniciar los servicios del stack '$stack_name'"
            error "⚠️ Los servicios permanecen detenidos. Reinícialos manualmente con:"
            error "   cd $DOCKER_DIR/$stack_name && docker compose up -d"
            # No retornamos error aquí para que el backup se considere exitoso
        fi
    fi

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

    # Inicializar stack-info PRIMERO (necesario para todas las operaciones)
    if ! init_stack_info; then
        error "No se pudo inicializar stack-info"
        exit 1
    fi

    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all|-a)
                backup_all=true
                shift
                ;;
            --safe|-s)
                SAFE_MODE=true
                log "🔒 Modo seguro activado: los servicios se detendrán durante el backup"
                shift
                ;;
            --cleanup|-c)
                CLEANUP_MODE=true
                # Verificar si el siguiente argumento es un número (cantidad de backups a mantener)
                if [[ $# -gt 1 && $2 =~ ^[0-9]+$ ]]; then
                    KEEP_BACKUPS="$2"
                    shift 2
                else
                    shift
                fi
                log "🧹 Modo limpieza activado: manteniendo $KEEP_BACKUPS backups por stack"
                ;;
            --restore|-r)
                RESTORE_MODE=true
                # Verificar si el siguiente argumento es un archivo de backup o un stack
                if [[ $# -gt 1 ]]; then
                    if [[ -f "$2" ]]; then
                        # Es un archivo de backup específico
                        RESTORE_BACKUP="$2"
                        shift 2
                    elif [[ "$2" != -* ]]; then
                        # Es un stack, mostrar menú de selección
                        RESTORE_STACK="$2"
                        shift 2
                    else
                        shift
                    fi
                else
                    shift
                fi
                ;;
            --verbose|-v)
                VERBOSE_MODE=true
                log "📝 Modo verbose activado: mostrando lista detallada de archivos"
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

    # Modo restore
    if [[ "$RESTORE_MODE" == "true" ]]; then
        local backup_to_restore=""

        if [[ -n "$RESTORE_BACKUP" ]]; then
            # Se especificó un archivo de backup
            backup_to_restore="$RESTORE_BACKUP"
        else
            # Mostrar menú de selección
            backup_to_restore=$(select_backup "$RESTORE_STACK")

            if [[ -z "$backup_to_restore" ]]; then
                exit 1
            fi
        fi

        # Realizar restore
        if restore_backup "$backup_to_restore" "$RESTORE_STACK"; then
            log "────────────────────────────────────────"
            log "✅ Proceso de restore completado exitosamente"
            exit 0
        else
            error "❌ El proceso de restore falló"
            exit 1
        fi
    fi

    # Verificar directorio de backups
    if ! check_backup_directory; then
        exit 1
    fi

    local start_time=$(date +%s)
    log "🚀 Iniciando proceso de backup ($(date))"

    # Si solo se solicita limpieza, ejecutar y salir
    if [[ "$CLEANUP_MODE" == "true" && ${#stacks_to_backup[@]} -eq 0 && "$backup_all" == "false" ]]; then
        cleanup_old_backups "$KEEP_BACKUPS"
        log "🎉 Proceso de limpieza completado"
        exit 0
    fi

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

    # Si no se especificaron stacks y no es solo limpieza, mostrar ayuda
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

    # Ejecutar limpieza de backups antiguos si está activada
    if [[ "$CLEANUP_MODE" == "true" ]]; then
        log "────────────────────────────────────────"
        cleanup_old_backups "$KEEP_BACKUPS"
    fi

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
  --all, -a               Respaldar todos los stacks disponibles
  --safe, -s              Modo seguro: detener servicios antes del backup y reiniciarlos después
  --cleanup, -c [N]       Limpiar backups antiguos, mantener N más recientes por stack (por defecto: 5)
  --restore, -r [STACK|FILE] Restaurar un backup (usa fzf para selección interactiva)
  --verbose, -v           Mostrar lista detallada de todos los archivos incluidos en el backup
  --help, -h              Mostrar esta ayuda

ARGUMENTOS:
  stack1, stack2, ...  Nombres de stacks específicos a respaldar

EJEMPLOS:
  $0 media                    # Backup solo del stack media
  $0 platform home            # Backup de platform y home
  $0 --all                    # Backup de todos los stacks
  $0 --safe media             # Backup seguro de media (detiene y reinicia servicios)
  $0 --all --safe             # Backup seguro de todos los stacks
  $0 --verbose media          # Backup con lista detallada de archivos
  $0 --cleanup                # Solo limpiar backups antiguos (mantener 5 por stack)
  $0 --cleanup 10             # Solo limpiar backups antiguos (mantener 10 por stack)
  $0 --all --cleanup 3        # Backup de todos + limpiar manteniendo 3 por stack
  $0 --restore                # Mostrar todos los backups y elegir cuál restaurar
  $0 --restore media          # Mostrar backups del stack media y elegir cuál restaurar
  $0 --restore /path/to/media-20251112-120000.tar.gz  # Restaurar backup específico

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
  - La restauración SOBRESCRIBE archivos existentes pero NO elimina otros archivos
  - Los directorios excluidos se mantienen intactos durante la restauración

DEPENDENCIAS:
  - fzf (requerido para --restore): Instalación:
    * Ubuntu/Debian: sudo apt install fzf
    * macOS: brew install fzf
    * Fedora/RHEL: sudo dnf install fzf
EOF
}

# Ejecutar función principal si el script se ejecuta directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
