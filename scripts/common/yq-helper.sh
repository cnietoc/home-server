#!/usr/bin/env bash

# Helper para trabajar con yq de forma compatible con diferentes versiones
# Soporta tanto yq-go (versión moderna) como yq-python (versión antigua)

# Variables globales para almacenar la versión detectada
YQ_VERSION=""
YQ_SYNTAX=""

# Detectar qué versión de yq está instalada
detect_yq_version() {
    if ! command -v yq >/dev/null 2>&1; then
        return 1
    fi

    # Verificar si es yq-go (versión correcta)
    if yq --version 2>&1 | grep -q "mikefarah/yq"; then
        YQ_VERSION="go"
        YQ_SYNTAX="eval"
        return 0
    fi

    # Verificar si tiene el comando 'eval' (característica de yq-go)
    if yq eval --version >/dev/null 2>&1; then
        YQ_VERSION="go"
        YQ_SYNTAX="eval"
        return 0
    fi

    # Si no es yq-go, asumir que es yq-python
    YQ_VERSION="python"
    YQ_SYNTAX=""
    return 0
}

# Ejecutar yq con la sintaxis correcta según la versión
run_yq() {
    local query="$1"
    local file="$2"

    # Detectar versión si no se ha hecho aún
    if [[ -z "$YQ_VERSION" ]]; then
        detect_yq_version || return 1
    fi

    if [[ "$YQ_VERSION" == "go" ]]; then
        # yq-go usa 'eval' como subcomando
        yq eval "$query" "$file"
    else
        # yq-python usa directamente el query
        yq "$query" "$file"
    fi
}

# Ejecutar yq in-place (modifica el archivo)
run_yq_inplace() {
    local query="$1"
    local file="$2"

    # Detectar versión si no se ha hecho aún
    if [[ -z "$YQ_VERSION" ]]; then
        detect_yq_version || return 1
    fi

    if [[ "$YQ_VERSION" == "go" ]]; then
        # yq-go soporta -i directamente
        yq eval -i "$query" "$file"
    else
        # yq-python necesita workaround con archivo temporal
        local temp_file="${file}.tmp"
        yq "$query" "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}

# Verificar que yq está instalado y funciona
check_yq() {
    if ! detect_yq_version; then
        echo "❌ yq no está instalado o no funciona correctamente." >&2
        echo "Instálalo con:" >&2
        echo "  - Ubuntu/Debian: sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq" >&2
        echo "  - macOS: brew install yq" >&2
        echo "  - Fedora/RHEL: sudo dnf install yq" >&2
        return 1
    fi
    return 0
}

# Exportar funciones para que puedan ser usadas por otros scripts
export -f detect_yq_version
export -f run_yq
export -f run_yq_inplace
export -f check_yq

