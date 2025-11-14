#!/usr/bin/env bash

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente." >&2
    exit 1
}

# === Funciones Wrapper para Snap ===
# Cuando yq se instala con Snap, tiene restricciones de acceso a archivos
# Workaround: usar stdin en lugar de pasar el archivo como argumento

# Leer de un archivo YAML (compatible con Snap)
yq::read() {
    local query="$1"
    local file="$2"

    # Usar stdin para evitar restricciones de Snap
    yq eval "$query" < "$file"
}

# Escribir a un archivo YAML in-place (compatible con Snap)
yq::write() {
    local query="$1"
    local file="$2"

    # Usar stdin/stdout para evitar restricciones de Snap
    local temp_file="${file}.tmp"
    yq eval "$query" < "$file" > "$temp_file" && mv "$temp_file" "$file"
}

# Alias para compatibilidad con código existente
yq_read() {
    yq::read "$@"
}

