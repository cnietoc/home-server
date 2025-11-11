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
    local config_dir="$PLATFORM_PROJECT_ROOT/data/platform/samba"

    # Crear directorio de configuración
    mkdir -p "$config_dir"

    # Obtener stacks que tienen shares
    local stacks_with_shares
    stacks_with_shares=$(get_stacks_with_shares 2>/dev/null || echo "")

    if [[ -z "$stacks_with_shares" ]]; then
        echo "ℹ️ No se encontraron stacks con shares, Samba no tendrá shares configuradas"

        # Crear override vacío
        cat > "$override_file" << 'EOF'
# Docker compose override generado automáticamente para Samba
# Este archivo se regenera en cada deploy
version: '3.8'

services:
  samba:
    volumes:
      - ${STACK_DATA}/samba:/config
EOF
        return 0
    fi

    echo "📁 Encontrados stacks con shares: $(echo "$stacks_with_shares" | tr '\n' ' ')"

    # Generar configuración de Samba
    local samba_conf="$config_dir/smb.conf"

    cat > "$samba_conf" << EOF
# Archivo smb.conf generado automáticamente
# Generado: $(date)

[global]
    workgroup = ${SAMBA_WORKGROUP:-WORKGROUP}
    server string = Home Server Samba
    security = user
    map to guest = never
    guest account = nobody

    # Configuración de red
    bind interfaces only = no
    interfaces = eth0

    # Configuración de logs
    log file = /var/log/samba/%m.log
    max log size = 1000

    # Configuración de seguridad
    encrypt passwords = yes
    null passwords = no

    # Configuración de navegación
    browseable = yes

    # Configuración de performance
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
    read raw = yes
    write raw = yes

EOF

    # Generar override de docker-compose con volúmenes dinámicos
    cat > "$override_file" << 'EOF'
# Docker compose override generado automáticamente para Samba
# Este archivo se regenera en cada deploy

services:
  samba:
    volumes:
      - ${STACK_DATA}/samba:/config
EOF

    # Procesar cada stack con shares
    local share_count=0
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

            # Generar nombre del share usando exposed_path (sin barra inicial para evitar doble barra)
            local samba_share_name="${exposed_path#/}"  # Remover barra inicial si existe
            local container_path="/shares/${samba_share_name}"

            echo "    📂 Share: $samba_share_name ($path -> $container_path)"

            # Añadir volumen al override
            if [[ "$permissions" == "ro" ]]; then
                echo "      - $path:$container_path:ro" >> "$override_file"
            else
                echo "      - $path:$container_path" >> "$override_file"
            fi

            # Añadir configuración al smb.conf
            cat >> "$samba_conf" << EOF

[$samba_share_name]
    comment = $description
    path = $container_path
    browseable = yes
    guest ok = no
    public = no
    valid users = ${SAMBA_USERNAME:-smbuser}
EOF

            if [[ "$permissions" == "ro" ]]; then
                echo "    writable = no" >> "$samba_conf"
                echo "    read only = yes" >> "$samba_conf"
            else
                echo "    writable = yes" >> "$samba_conf"
                echo "    read only = no" >> "$samba_conf"
                echo "    create mask = 0664" >> "$samba_conf"
                echo "    directory mask = 0775" >> "$samba_conf"
            fi

            share_count=$((share_count + 1))

        done <<< "$shares"

    done <<< "$stacks_with_shares"

    echo "✅ Samba configurado con $share_count shares"
    echo "📝 Archivos generados:"
    echo "  - $override_file"
    echo "  - $samba_conf"
}

# Ejecutar configuración
echo "🚀 Iniciando pre-deploy del stack platform..."
configure_samba
echo "✅ Pre-deploy del stack platform completado"
