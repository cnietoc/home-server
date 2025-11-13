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

    # Si no es yq-go, es yq-python (versión antigua pero soportada)
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
        # Sintaxis: yq eval 'query' archivo
        yq eval "$query" "$file"
    else
        # yq-python es un wrapper de jq que espera sintaxis de jq
        # Sintaxis: yq 'jq_filter' archivo
        # Nota: yq-python usa sintaxis de jq, no de yq-go
        # Ejemplo: '.stacks | keys | .[]' funciona igual que en jq
        yq -r "$query" "$file"
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
        # yq-python: convertir a JSON, modificar con jq, convertir de vuelta a YAML
        local temp_json="${file}.tmp.json"
        local temp_yaml="${file}.tmp.yaml"

        # Convertir YAML a JSON
        yq -j . "$file" > "$temp_json" 2>/dev/null || {
            echo "❌ Error convirtiendo YAML a JSON" >&2
            rm -f "$temp_json"
            return 1
        }

        # Traducir query de yq-go a jq y aplicar modificación
        local jq_query
        jq_query=$(translate_yq_to_jq "$query")

        if [[ -n "$jq_query" ]]; then
            jq "$jq_query" "$temp_json" > "${temp_json}.new" 2>/dev/null || {
                echo "❌ Error aplicando modificación con jq" >&2
                rm -f "$temp_json" "${temp_json}.new"
                return 1
            }
            mv "${temp_json}.new" "$temp_json"
        fi

        # Convertir JSON de vuelta a YAML
        yq -y . "$temp_json" > "$temp_yaml" 2>/dev/null || {
            echo "❌ Error convirtiendo JSON a YAML" >&2
            rm -f "$temp_json" "$temp_yaml"
            return 1
        }

        # Reemplazar archivo original
        mv "$temp_yaml" "$file"
        rm -f "$temp_json"
    fi
}

# Traducir query de yq-go a jq (para yq-python)
translate_yq_to_jq() {
    local query="$1"

    # Detectar y traducir operaciones comunes
    if [[ "$query" =~ ^(.+)\ =\ (.+)$ ]]; then
        # Operación de asignación: .path = value
        local path="${BASH_REMATCH[1]}"
        local value="${BASH_REMATCH[2]}"

        # Limpiar espacios
        path=$(echo "$path" | xargs)
        value=$(echo "$value" | xargs)

        # El path ya viene en formato correcto (.server.config_hash)
        # Solo necesitamos asegurarnos de que el value esté correctamente formateado

        # Generar query jq
        if [[ "$value" =~ ^\".*\"$ ]]; then
            # Ya tiene comillas
            echo "$path = $value"
        elif [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]] || [[ "$value" == "null" ]]; then
            # Valor numérico o booleano o null
            echo "$path = $value"
        else
            # Necesita comillas
            echo "$path = \"$value\""
        fi
    elif [[ "$query" =~ ^del\((.+)\)$ ]]; then
        # Operación de eliminación: del(.path)
        local path="${BASH_REMATCH[1]}"
        # El path ya viene correcto
        echo "del($path)"
    else
        # Query no soportado
        echo ""
    fi
}

# Verificar que yq está instalado y funciona
check_yq() {
    # Siempre detectar la versión primero
    if ! detect_yq_version; then
        echo "❌ yq no está instalado o no funciona correctamente." >&2
        echo "Instálalo con:" >&2
        echo "  - Ubuntu/Debian: sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq" >&2
        echo "  - macOS: brew install yq" >&2
        echo "  - Fedora/RHEL: sudo dnf install yq" >&2
        return 1
    fi

    # Si es yq-python, verificar que jq esté instalado (necesario para modificaciones)
    if [[ "$YQ_VERSION" == "python" ]] && ! command -v jq >/dev/null 2>&1; then
        echo "❌ yq-python detectado, pero jq no está instalado (necesario para modificaciones)." >&2
        echo "Instala jq con:" >&2
        echo "  - Ubuntu/Debian: sudo apt install jq" >&2
        echo "  - macOS: brew install jq" >&2
        echo "  - Fedora/RHEL: sudo dnf install jq" >&2
        return 1
    fi

    return 0
}

# Exportar funciones para que puedan ser usadas por otros scripts
export -f detect_yq_version
export -f run_yq
export -f run_yq_inplace
export -f translate_yq_to_jq
export -f check_yq

