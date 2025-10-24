#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Importar funciones comunes
source "$SCRIPT_DIR/common/env-loader.sh"

# Función para verificar que Docker está disponible
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log "❌ Docker no está instalado o no está en el PATH"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log "❌ Docker no está corriendo o no tienes permisos"
        log "Inicia Docker Desktop o ejecuta: sudo systemctl start docker"
        return 1
    fi

    log "✅ Docker está disponible y corriendo"
}

# Crear red Docker necesaria
create_docker_networks() {
    load_common_config
    local proxy_network="${PROXY_NETWORK:-proxy}"

    # Crear red proxy (para Traefik y servicios web)
    log "Verificando red proxy: $proxy_network"
    if docker network ls --format "{{.Name}}" | grep -q "^$proxy_network$"; then
        log "⏭️ La red $proxy_network ya existe"
    else
        log "Creando red proxy: $proxy_network"
        docker network create "$proxy_network"
        log "✅ Red proxy $proxy_network creada"
    fi
}

# Función para verificar permisos
check_permissions() {
    load_common_config
    local data_root="${DATA_ROOT:-$PROJECT_ROOT/data}"

    log "Verificando permisos en $data_root..."

    if [[ -d "$data_root" ]]; then
        find "$data_root" -type d -exec ls -ld {} \; | head -10

        log "Si hay problemas de permisos, ejecuta:"
        log "sudo chown -R ${PUID:-1000}:${PGID:-1000} $data_root"
    else
        log "⚠️ El directorio $data_root no existe. Ejecuta: $0 create"
    fi
}

# Función principal
main() {
    case "${1:-create}" in
        "create"|"init")
            check_docker
            create_docker_networks
            ;;
        "check"|"perms")
            check_permissions
            ;;
        "networks"|"network")
            check_docker
            create_docker_networks
            ;;
        *)
            echo "Uso: $0 [networks|check]"
            echo "  networks:  Crear redes Docker necesarias (default)"
            echo "  check:     Verificar permisos en directorios existentes"
            exit 1
            ;;
    esac
}

main "$@"
