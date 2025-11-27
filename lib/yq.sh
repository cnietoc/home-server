#!/usr/bin/env bash

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente." >&2
    exit 1
}

# === Detección de instalación ===
# Detectar si yq está instalado via snap
yq::is_snap() {
    command -v yq >/dev/null 2>&1 || return 1
    local yq_path
    yq_path=$(command -v yq)
    [[ "$yq_path" =~ /snap/ ]]
}

# Ejecutar yq (usando Docker si está en snap)
yq::exec() {
    if yq::is_snap; then
        # Ejecutar con Docker para evitar restricciones de snap
        docker run --rm -i -v "${PWD}":/workdir mikefarah/yq "$@"
    else
        # Ejecutar yq nativo
        yq "$@"
    fi
}

# === Funciones Wrapper ===
# Cuando yq se instala con Snap, tiene restricciones de acceso a archivos
# Workaround: usar Docker o stdin según la instalación

# Leer de un archivo YAML (compatible con Snap)
yq::read() {
    local query="$1"
    local file="$2"

    if yq::is_snap; then
        # Usar Docker con volumen montado
        local abs_file
        abs_file=$(realpath "$file")
        local dir
        dir=$(dirname "$abs_file")
        local filename
        filename=$(basename "$abs_file")
        docker run --rm -i -v "$dir":/workdir mikefarah/yq eval "$query" "/workdir/$filename"
    else
        # Usar stdin para evitar problemas de permisos
        yq eval "$query" < "$file"
    fi
}

# Escribir a un archivo YAML in-place (compatible con Snap)
yq::write() {
    local query="$1"
    local file="$2"

    if yq::is_snap; then
        # Usar Docker con volumen montado
        local abs_file
        abs_file=$(realpath "$file")
        local dir
        dir=$(dirname "$abs_file")
        local filename
        filename=$(basename "$abs_file")
        local temp_file="${file}.tmp"
        docker run --rm -i -v "$dir":/workdir mikefarah/yq eval "$query" "/workdir/$filename" > "$temp_file" && mv "$temp_file" "$file"
    else
        # Usar stdin/stdout para evitar problemas de permisos
        local temp_file="${file}.tmp"
        yq eval "$query" < "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}

# Alias para compatibilidad con código existente
yq_read() {
    yq::read "$@"
}

