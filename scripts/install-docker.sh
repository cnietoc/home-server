#!/usr/bin/env bash
set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función de logging con colores
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $*"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $*"
}

info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️${NC} $*"
}

# Verificar que se ejecuta en Ubuntu
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        error "No se puede determinar el sistema operativo"
        exit 1
    fi

    . /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        error "Este script está diseñado para Ubuntu. Sistema detectado: $ID"
        exit 1
    fi

    log "✅ Ubuntu detectado: $VERSION"
}

# Verificar permisos de sudo
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        warn "Ejecutándose como root. Recomendado ejecutar como usuario normal con sudo."
    fi

    if ! sudo -v >/dev/null 2>&1; then
        error "Este script requiere permisos de sudo"
        exit 1
    fi

    log "✅ Permisos de sudo verificados"
}

# Actualizar sistema
update_system() {
    log "🔄 Actualizando lista de paquetes..."
    sudo apt-get update

    log "🔄 Actualizando paquetes instalados..."
    sudo apt-get upgrade -y

    log "✅ Sistema actualizado"
}

# Instalar dependencias básicas
install_basic_deps() {
    log "📦 Instalando dependencias básicas..."

    local packages=(
        curl
        wget
        gnupg
        lsb-release
        ca-certificates
        apt-transport-https
        software-properties-common
        git
        jq
        htop
        unzip
        vim
        nano
        net-tools
        ufw
    )

    for package in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $package "; then
            info "$package ya está instalado"
        else
            log "Instalando $package..."
            sudo apt-get install -y "$package"
        fi
    done

    log "✅ Dependencias básicas instaladas"
}

# Verificar si Docker ya está instalado
check_docker_installed() {
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        info "Docker ya está instalado: versión $docker_version"

        # Verificar si el servicio está corriendo
        if sudo systemctl is-active --quiet docker; then
            info "Servicio Docker está corriendo"
        else
            warn "Servicio Docker no está corriendo, iniciándolo..."
            sudo systemctl start docker
            sudo systemctl enable docker
        fi

        return 0
    else
        return 1
    fi
}

# Remover Docker snap si existe para evitar conflictos
remove_docker_snap() {
    if command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
        warn "Docker snap detectado. Removiendo para evitar conflictos..."
        sudo snap remove docker
        log "✅ Docker snap desinstalado"
    else
        info "No se encontró Docker snap instalado"
    fi
}

# Instalar Docker
install_docker() {
    if check_docker_installed; then
        return 0
    fi

    log "🐳 Instalando Docker..."

    # Remover Docker snap primero
    remove_docker_snap

    # Eliminar versiones antiguas si existen
    log "Eliminando versiones antiguas de Docker..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Añadir repositorio oficial de Docker
    log "Configurando repositorio oficial de Docker..."

    # Verificar si la clave GPG ya existe
    local gpg_keyring="/usr/share/keyrings/docker-archive-keyring.gpg"
    if [[ ! -f "$gpg_keyring" ]]; then
        log "Descargando clave GPG de Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o "$gpg_keyring"
        log "✅ Clave GPG de Docker instalada"
    else
        info "Clave GPG de Docker ya existe"
    fi

    # Verificar si el repositorio ya está configurado
    local docker_list="/etc/apt/sources.list.d/docker.list"
    if [[ ! -f "$docker_list" ]] || ! grep -q "download.docker.com" "$docker_list"; then
        log "Añadiendo repositorio de Docker..."
        echo "deb [arch=$(dpkg --print-architecture) signed-by=$gpg_keyring] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee "$docker_list" > /dev/null
        log "✅ Repositorio de Docker configurado"
    else
        info "Repositorio de Docker ya está configurado"
    fi

    # Actualizar lista de paquetes con el nuevo repositorio
    sudo apt-get update

    # Instalar Docker Engine
    log "Instalando Docker Engine, CLI y containerd..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Iniciar y habilitar Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    log "✅ Docker instalado correctamente"
}

# Configurar Docker para el usuario actual
configure_docker_user() {
    local current_user=$(whoami)

    if [[ "$current_user" == "root" ]]; then
        warn "Ejecutándose como root, saltando configuración de grupo docker"
        return 0
    fi

    log "👤 Configurando Docker para el usuario: $current_user"

    # Crear grupo docker si no existe
    if ! getent group docker >/dev/null; then
        sudo groupadd docker
        log "Grupo docker creado"
    fi

    # Añadir usuario al grupo docker si no está ya
    if groups "$current_user" | grep -q docker; then
        info "Usuario $current_user ya está en el grupo docker"
    else
        sudo usermod -aG docker "$current_user"
        log "Usuario $current_user añadido al grupo docker"
        warn "⚠️ Necesitarás cerrar sesión y volver a entrar para que los cambios tengan efecto"
        warn "   O ejecutar: newgrp docker"
    fi
}

# Verificar instalación de Docker
verify_docker() {
    log "🔍 Verificando instalación de Docker..."

    # Verificar comando docker
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker no está en el PATH"
        return 1
    fi

    # Verificar servicio
    if ! sudo systemctl is-active --quiet docker; then
        error "Servicio Docker no está corriendo"
        return 1
    fi

    # Verificar funcionalidad básica
    if sudo docker run --rm hello-world >/dev/null 2>&1; then
        log "✅ Docker funciona correctamente"
    else
        error "Docker instalado pero no funciona correctamente"
        return 1
    fi

    # Mostrar versiones
    local docker_version=$(docker --version)
    local compose_version=$(docker compose version 2>/dev/null || echo "Docker Compose no disponible")

    log "📋 Versiones instaladas:"
    log "   $docker_version"
    log "   $compose_version"
}



# Optimizaciones del sistema para Docker
optimize_system() {
    log "⚙️ Aplicando optimizaciones del sistema para Docker..."

    # Configurar límites de archivos abiertos
    local limits_file="/etc/security/limits.conf"
    if ! grep -q "# Docker optimizations" "$limits_file"; then
        cat << EOF | sudo tee -a "$limits_file" >/dev/null

# Docker optimizations
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF
        log "Límites de archivos abiertos configurados"
    else
        info "Límites de archivos ya configurados"
    fi

    # Configurar parámetros del kernel
    local sysctl_file="/etc/sysctl.d/99-docker.conf"
    if [[ ! -f "$sysctl_file" ]]; then
        cat << EOF | sudo tee "$sysctl_file" >/dev/null
# Docker optimizations
vm.max_map_count=262144
fs.file-max=2097152
net.core.somaxconn=65535
EOF
        sudo sysctl -p "$sysctl_file"
        log "Parámetros del kernel optimizados"
    else
        info "Parámetros del kernel ya optimizados"
    fi

    log "✅ Optimizaciones aplicadas"
}



# Función para mostrar información final
show_final_info() {
    log "🎉 Instalación completada exitosamente!"
    echo ""
    log "📋 Resumen de lo instalado:"
    log "   ✅ Docker Engine y Docker Compose"
    log "   ✅ Dependencias básicas (curl, git, jq, etc.)"
    log "   ✅ Optimizaciones del sistema"
    echo ""
    log "🚀 Próximos pasos:"
    log "   1. Reinicia la sesión o ejecuta: newgrp docker"
    log "   2. Verifica Docker: docker run hello-world"
    log "   3. Clona tu repositorio home-server"
    log "   4. Configura tus secretos y despliega los stacks"
    echo ""
    warn "⚠️ IMPORTANTE: Reinicia tu sesión SSH para que los cambios del grupo docker tengan efecto"
}

# Función de ayuda
show_help() {
    cat << EOF
Uso: $0 [opciones]

DESCRIPCIÓN:
  Instala Docker, Docker Compose y dependencias en Ubuntu Server.
  El script es idempotente (se puede ejecutar múltiples veces).

OPCIONES:
  --skip-optimize    No aplicar optimizaciones del sistema
  --help             Mostrar esta ayuda

EJEMPLOS:
  $0                       # Instalación completa
  $0 --skip-optimize       # Sin optimizaciones del sistema

PREREQUISITOS:
  - Ubuntu Server (18.04 o superior)
  - Usuario con permisos sudo
  - Conexión a internet

EOF
}

# Función principal
main() {
    local skip_optimize=false

    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-optimize)
                skip_optimize=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done

    log "🚀 Iniciando instalación de Docker en Ubuntu Server..."
    echo ""

    # Verificaciones iniciales
    check_ubuntu
    check_sudo

    # Instalación
    update_system
    install_basic_deps
    install_docker
    configure_docker_user
    verify_docker

    # Configuraciones opcionales

    if [[ "$skip_optimize" != "true" ]]; then
        optimize_system
    else
        info "⏭️ Optimizaciones del sistema omitidas"
    fi

    # Información final
    show_final_info
}

# Manejar señales de interrupción
trap 'error "Instalación interrumpida"; exit 130' INT TERM

# Ejecutar función principal
main "$@"
