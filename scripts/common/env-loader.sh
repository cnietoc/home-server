#!/usr/bin/env bash

get_project_root() {
    # Desde env-loader.sh (scripts/common/) necesitamos subir 2 niveles para llegar a la raíz
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root="$(dirname "$(dirname "$script_dir")")"
    echo "$project_root"
}

get_private_dir() {
    local project_root="$(get_project_root)"
    local private_dir="$project_root/config/private"

    if [[ ! -L "$private_dir" ]]; then
        echo "❌ Error: Enlace simbólico no encontrado: $private_dir" >&2
        echo "Crea el enlace: ./scripts/link-config.sh /ruta/a/tu/configuracion" >&2
        return 1
    fi

    if [[ ! -d "$private_dir" ]]; then
        echo "❌ Error: El enlace apunta a una carpeta inexistente: $private_dir" >&2
        return 1
    fi

    echo "$private_dir"
}

load_env() {
    local env_file="$1"
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
        echo "[$(date '+%H:%M:%S')] ✅ Cargado: $(basename "$env_file")"
        return 0
    else
        echo "[$(date '+%H:%M:%S')] ⚠️ No encontrado: $(basename "$env_file")"
        return 1
    fi
}

load_common_config() {
    local private_dir
    if ! private_dir="$(get_private_dir)"; then
        return 1
    fi
    load_env "$private_dir/common.env" || true
}

# Cargar configuraciones específicas
load_config() {
    local config_types=("$@")
    local private_dir
    if ! private_dir="$(get_private_dir)"; then
        return 1
    fi

    for config_type in "${config_types[@]}"; do
        load_env "$private_dir/$config_type.env" || true
    done
}

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}
