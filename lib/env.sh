#!/usr/bin/env bash
# ============================================
# lib/env.sh — Carga de variables de entorno
# ============================================

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente." >&2
    exit 1
}

_ENV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_ENV_LIB_DIR/logs.sh"
source "$_ENV_LIB_DIR/yq.sh"

_env::get_project_root() {
    local project_root="$(dirname "$_ENV_LIB_DIR")"
    echo "$project_root"
}

_env::get_private_dir() {
    local project_root="$(_env::get_project_root)"
    local private_dir="$project_root/config/private"

    if [[ ! -L "$private_dir" ]]; then
        log_error "❌ Error: Enlace simbólico no encontrado: $private_dir" >&2
        log "Crea el enlace: ./scripts/link-config.sh /ruta/a/tu/configuracion" >&2
        return 1
    fi

    if [[ ! -d "$private_dir" ]]; then
        logs::info "El enlace apunta a una carpeta inexistente: $private_dir" >&2
        return 1
    fi

    echo "$private_dir"
}

_env::load_env() {
    local env_file="$1"
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
        return 0
    else
        logs::error "⚠️ No encontrado: $(basename "$env_file")"
        return 1
    fi
}

_env::load_common_config() {
    local private_dir
    if ! private_dir="$(_env::get_private_dir)"; then
        return 1
    fi
    _env::load_env "$private_dir/common.env" || true
}

# Cargar configuraciones específicas
_env::load_config() {
    local config_types=("$@")
    local private_dir
    if ! private_dir="$(_env::get_private_dir)"; then
        return 1
    fi

    for config_type in "${config_types[@]}"; do
        _env::load_env "$private_dir/$config_type.env" || true
    done
}

env::load() {
    _env::load_common_config || return 1
    local config_types=("$@")
    if [[ "${#config_types[@]}" -gt 0 ]]; then
        _env::load_config "${config_types[@]}" || return 1
    fi
}
