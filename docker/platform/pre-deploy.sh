#!/bin/bash

# Pre-deploy script para stack platform
# Configura Samba dinámicamente basado en los shares de todos los stacks

set -euo pipefail

# Calcular directorios con nombres únicos para evitar conflictos
PLATFORM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_PROJECT_ROOT="$(dirname "$(dirname "$PLATFORM_SCRIPT_DIR")")"

# Cargar variables de entorno usando env-loader
source "$PLATFORM_PROJECT_ROOT/scripts/common/env-loader.sh"

# Cargar funciones de stack-info directamente
source "$PLATFORM_PROJECT_ROOT/scripts/stack-info.sh" || {
    echo "❌ Error: No se pudo cargar stack-info.sh" >&2
    exit 1
}

# Inicializar stack-info
if ! init_stack_info; then
    echo "❌ Error: No se pudo inicializar stack-info" >&2
    exit 1
fi

# Función para configurar Samba dinámicamente
configure_samba() {
    echo "🔧 Configurando Samba dinámicamente basado en shares..."

    local override_file="$PLATFORM_SCRIPT_DIR/docker-compose.override.yml"

    # Obtener stacks que tienen shares
    local stacks_with_shares
    stacks_with_shares=$(get_stacks_with_shares 2>/dev/null || echo "")

    if [[ -z "$stacks_with_shares" ]]; then
        echo "ℹ️ No se encontraron stacks con shares, Samba no tendrá shares configuradas"

        # Crear override básico sin shares
        cat > "$override_file" << 'EOF'
# Docker compose override generado automáticamente para Samba
# Este archivo se regenera en cada deploy

services:
  samba:
    volumes:
      - ${STACK_DATA}/samba:/config
EOF
        return 0
    fi

    echo "📁 Encontrados stacks con shares: $(echo "$stacks_with_shares" | tr '\n' ' ')"

    # Generar override con volúmenes dinámicos
    cat > "$override_file" << 'EOF'
# Docker compose override generado automáticamente para Samba
# Este archivo se regenera en cada deploy

services:
  samba:
    volumes:
      - ${STACK_DATA}/samba:/config
EOF

    # Generar comandos para dperson/samba
    local samba_commands=()
    local share_count=0

    # Configuración de usuario y workgroup
    samba_commands+=("-u" "\${SAMBA_USERNAME:-smbuser};\${SAMBA_PASSWORD:-changeme}")
    samba_commands+=("-w" "\${SAMBA_WORKGROUP:-WORKGROUP}")

    # Procesar shares de cada stack
    while IFS= read -r stack_name; do
        [[ -z "$stack_name" ]] && continue

        echo "  📋 Procesando stack: $stack_name"

        local shares
        shares=$(get_stack_shares "$stack_name" 2>/dev/null || echo "")

        while IFS= read -r share_name; do
            [[ -z "$share_name" ]] && continue

            local path exposed_path permissions description
            path=$(get_share_path "$stack_name" "$share_name" 2>/dev/null || echo "")
            exposed_path=$(get_share_exposed_path "$stack_name" "$share_name" 2>/dev/null || echo "")
            permissions=$(get_share_permissions "$stack_name" "$share_name" 2>/dev/null || echo "ro")
            description=$(get_share_description "$stack_name" "$share_name" 2>/dev/null || echo "")

            [[ -z "$path" ]] && continue

            # Generar nombre del share usando exposed_path
            local samba_share_name="${exposed_path#/}"
            local container_path="/shares/${samba_share_name}"

            echo "    📂 Share: $samba_share_name ($path -> $container_path)"

            # Añadir volumen al override
            if [[ "$permissions" == "ro" ]]; then
                echo "      - $path:$container_path:ro" >> "$override_file"
            else
                echo "      - $path:$container_path" >> "$override_file"
            fi

            # Configurar share para dperson/samba: -s "name;path;browsable;readonly;guest;users"
            local readonly="no"
            [[ "$permissions" == "ro" ]] && readonly="yes"

            samba_commands+=("-s" "$samba_share_name;$container_path;yes;$readonly;no;\${SAMBA_USERNAME:-smbuser}")

            share_count=$((share_count + 1))

        done <<< "$shares"

    done <<< "$stacks_with_shares"

    # Añadir comandos al override
    if [[ ${#samba_commands[@]} -gt 0 ]]; then
        echo "    command:" >> "$override_file"
        for cmd in "${samba_commands[@]}"; do
            echo "      - \"$cmd\"" >> "$override_file"
        done
    fi

    echo "✅ Samba configurado con $share_count shares"
    echo "📝 Archivos generados:"
    echo "  - $override_file"
}

# Ejecutar configuración
echo "🚀 Iniciando pre-deploy del stack platform..."
configure_samba
echo "✅ Pre-deploy del stack platform completado"
