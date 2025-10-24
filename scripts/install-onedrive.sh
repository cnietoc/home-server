#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/common/env-loader.sh"

# Colores para logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  $1${NC}"
}

# Verificar si rclone está instalado
check_rclone() {
    if command -v rclone >/dev/null 2>&1; then
        local version
        version=$(rclone version | head -n1)
        log "rclone ya está instalado: $version"
        return 0
    else
        return 1
    fi
}

# Instalar rclone
install_rclone() {
    log "🔧 Instalando rclone..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew >/dev/null 2>&1; then
            log "Instalando rclone via Homebrew..."
            brew install rclone
        else
            warn "Homebrew no encontrado. Instalando via script oficial..."
            curl https://rclone.org/install.sh | sudo bash
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get >/dev/null 2>&1; then
            log "Instalando rclone via apt..."
            sudo apt-get update
            sudo apt-get install -y rclone
        elif command -v yum >/dev/null 2>&1; then
            log "Instalando rclone via yum..."
            sudo yum install -y rclone
        else
            warn "Gestor de paquetes no soportado. Instalando via script oficial..."
            curl https://rclone.org/install.sh | sudo bash
        fi
    else
        warn "SO no soportado automáticamente. Instalando via script oficial..."
        curl https://rclone.org/install.sh | sudo bash
    fi

    if check_rclone; then
        log "✅ rclone instalado correctamente"
    else
        error "❌ Error al instalar rclone"
        exit 1
    fi
}

# Configurar OneDrive
configure_onedrive() {
    log "🔧 Configurando OneDrive con rclone..."

    info "Se abrirá el configurador interactivo de rclone."
    info "Sigue estos pasos:"
    echo
    info "1. Elige 'n' para nueva configuración remota"
    info "2. Nombre: 'onedrive' (o el que prefieras)"
    info "3. Tipo: Busca 'Microsoft OneDrive' y selecciona el número"
    info "4. client_id: Presiona Enter (vacío para usar el predeterminado)"
    info "5. client_secret: Presiona Enter (vacío para usar el predeterminado)"
    info "6. region: Elige '1' para Microsoft Cloud Global"
    info "7. Editar configuración avanzada: 'n' (no)"
    info "8. Auto config: 'y' (sí) - Se abrirá el navegador para autenticación"
    info "9. Tipo de configuración: Elige '1' para OneDrive Personal"
    info "10. Confirma con 'y' (sí) para mantener la configuración"
    echo
    warn "⚠️  Presiona ENTER cuando estés listo para continuar..."
    read -r

    rclone config

    log "✅ Configuración de OneDrive completada"
}

# Crear punto de montaje
create_mount_point() {
    local mount_dir="${1:-$HOME/OneDrive}"

    log "📁 Creando punto de montaje en: $mount_dir"

    if [[ ! -d "$mount_dir" ]]; then
        mkdir -p "$mount_dir"
        log "✅ Directorio de montaje creado: $mount_dir"
    else
        info "Directorio de montaje ya existe: $mount_dir"
    fi

    echo "$mount_dir"
}

# Crear script de montaje
create_mount_script() {
    local remote_name="$1"
    local mount_dir="$2"
    local script_path="$PROJECT_ROOT/scripts/mount-onedrive.sh"

    log "📝 Creando script de montaje: $script_path"

    cat > "$script_path" << EOF
#!/usr/bin/env bash
set -euo pipefail

# Script para montar OneDrive con rclone
REMOTE_NAME="$remote_name"
MOUNT_DIR="$mount_dir"

# Colores para logging
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "\${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] \$1\${NC}"
}

error() {
    echo -e "\${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ \$1\${NC}" >&2
}

warn() {
    echo -e "\${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  \$1\${NC}"
}

# Verificar si ya está montado
if mountpoint -q "\$MOUNT_DIR" 2>/dev/null; then
    warn "OneDrive ya está montado en \$MOUNT_DIR"
    exit 0
fi

# Crear directorio si no existe
mkdir -p "\$MOUNT_DIR"

# Montar OneDrive
log "🔗 Montando OneDrive..."
log "Directorio: \$MOUNT_DIR"
log "Remoto: \$REMOTE_NAME"

rclone mount "\$REMOTE_NAME": "\$MOUNT_DIR" \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-age 100h \\
    --vfs-cache-max-size 10G \\
    --vfs-cache-poll-interval 15s \\
    --dir-cache-time 5m \\
    --poll-interval 15s \\
    --umask 002 \\
    --uid $(id -u) \\
    --gid $(id -g) \\
    --allow-other \\
    --daemon

# Verificar montaje
sleep 2
if mountpoint -q "\$MOUNT_DIR" 2>/dev/null; then
    log "✅ OneDrive montado correctamente en \$MOUNT_DIR"
else
    error "❌ Error al montar OneDrive"
    exit 1
fi
EOF

    chmod +x "$script_path"
    log "✅ Script de montaje creado: $script_path"
}

# Crear script de desmontaje
create_unmount_script() {
    local mount_dir="$1"
    local script_path="$PROJECT_ROOT/scripts/unmount-onedrive.sh"

    log "📝 Creando script de desmontaje: $script_path"

    cat > "$script_path" << EOF
#!/usr/bin/env bash
set -euo pipefail

# Script para desmontar OneDrive
MOUNT_DIR="$mount_dir"

# Colores para logging
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "\${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] \$1\${NC}"
}

error() {
    echo -e "\${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ \$1\${NC}" >&2
}

warn() {
    echo -e "\${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  \$1\${NC}"
}

# Verificar si está montado
if ! mountpoint -q "\$MOUNT_DIR" 2>/dev/null; then
    warn "OneDrive no está montado en \$MOUNT_DIR"
    exit 0
fi

log "🔓 Desmontando OneDrive de \$MOUNT_DIR..."

# Desmontar
if fusermount -u "\$MOUNT_DIR" 2>/dev/null || umount "\$MOUNT_DIR" 2>/dev/null; then
    log "✅ OneDrive desmontado correctamente"
else
    error "❌ Error al desmontar OneDrive"
    exit 1
fi
EOF

    chmod +x "$script_path"
    log "✅ Script de desmontaje creado: $script_path"
}

# Crear servicio systemd (solo Linux)
create_systemd_service() {
    local remote_name="$1"
    local mount_dir="$2"

    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        info "Creación de servicio systemd omitida (no es Linux)"
        return 0
    fi

    log "📝 Creando servicio systemd..."

    local service_content
    service_content="[Unit]
Description=OneDrive (rclone)
AssertPathIsDirectory=$mount_dir
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount $remote_name: $mount_dir --config=%h/.config/rclone/rclone.conf --vfs-cache-mode writes --vfs-cache-max-age 100h --vfs-cache-max-size 10G --allow-other --uid $(id -u) --gid $(id -g)
ExecStop=/bin/fusermount -u $mount_dir
User=%i
Group=%i
Restart=always
RestartSec=10

[Install]
WantedBy=default.target"

    echo "$service_content" | sudo tee /etc/systemd/system/onedrive-rclone@.service > /dev/null

    info "Para habilitar el servicio automático, ejecuta:"
    info "  sudo systemctl enable onedrive-rclone@\$USER.service"
    info "  sudo systemctl start onedrive-rclone@\$USER.service"
}

# Mostrar resumen final
show_summary() {
    local remote_name="$1"
    local mount_dir="$2"

    echo
    log "🎉 Instalación y configuración de OneDrive completada!"
    echo
    info "📋 Resumen:"
    info "  • rclone instalado y configurado"
    info "  • Remoto configurado: $remote_name"
    info "  • Punto de montaje: $mount_dir"
    info "  • Scripts creados en: $PROJECT_ROOT/scripts/"
    echo
    info "🚀 Para montar OneDrive:"
    info "  ./scripts/mount-onedrive.sh"
    echo
    info "🛑 Para desmontar OneDrive:"
    info "  ./scripts/unmount-onedrive.sh"
    echo
    info "📊 Para ver el estado:"
    info "  rclone about $remote_name:"
    echo
    info "🔧 Para gestionar la configuración:"
    info "  rclone config"
    echo
}

# Función principal
main() {
    log "🚀 Iniciando instalación y configuración de OneDrive con rclone..."

    # Verificar/instalar rclone
    if ! check_rclone; then
        install_rclone
    fi

    # Configurar OneDrive
    info "¿Quieres configurar OneDrive ahora? (y/n)"
    read -r configure_now

    if [[ "$configure_now" =~ ^[Yy]$ ]]; then
        configure_onedrive
    else
        info "Puedes configurar OneDrive más tarde ejecutando: rclone config"
        exit 0
    fi

    # Obtener nombre del remoto configurado
    info "¿Cuál es el nombre del remoto que configuraste? (por defecto: onedrive)"
    read -r remote_name
    remote_name="${remote_name:-onedrive}"

    # Verificar que el remoto existe
    if ! rclone listremotes | grep -q "^${remote_name}:$"; then
        error "Remoto '$remote_name' no encontrado. Remotos disponibles:"
        rclone listremotes
        exit 1
    fi

    # Crear punto de montaje
    info "¿Dónde quieres montar OneDrive? (por defecto: $HOME/OneDrive)"
    read -r mount_location
    mount_dir="${mount_location:-$HOME/OneDrive}"
    mount_dir=$(create_mount_point "$mount_dir")

    # Crear scripts auxiliares
    create_mount_script "$remote_name" "$mount_dir"
    create_unmount_script "$mount_dir"
    create_systemd_service "$remote_name" "$mount_dir"

    # Mostrar resumen
    show_summary "$remote_name" "$mount_dir"
}

# Ejecutar función principal
main "$@"
