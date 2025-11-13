#!/usr/bin/env bash

# Helper para trabajar con yq (mikefarah/yq versión Go)
# Requiere yq-go instalado en el sistema

# Verificar que yq-go está instalado al cargar el script
_verify_yq_go() {
    if ! command -v yq >/dev/null 2>&1; then
        echo "❌ ERROR: yq no está instalado" >&2
        echo "" >&2
        echo "Instala yq-go con uno de estos métodos:" >&2
        echo "  1. Descarga directa (recomendado):" >&2
        echo "     sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq" >&2
        echo "     sudo chmod +x /usr/local/bin/yq" >&2
        echo "" >&2
        echo "  2. Homebrew:" >&2
        echo "     brew install yq" >&2
        echo "" >&2
        echo "  3. Snap:" >&2
        echo "     snap install yq" >&2
        return 1
    fi

    # Verificar que es yq-go (mikefarah/yq) y no otra versión
    if ! yq --version 2>&1 | grep -q "mikefarah/yq"; then
        echo "❌ ERROR: yq instalado no es la versión correcta" >&2
        echo "" >&2
        echo "Detectado: $(yq --version 2>&1 | head -1)" >&2
        echo "Requerido: yq de mikefarah (https://github.com/mikefarah/yq)" >&2
        echo "" >&2
        echo "Si tienes yq-python instalado, desinst álalo primero:" >&2
        echo "  sudo apt remove python3-yq  # o pip uninstall yq" >&2
        echo "" >&2
        echo "Luego instala yq-go:" >&2
        echo "  sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq" >&2
        echo "  sudo chmod +x /usr/local/bin/yq" >&2
        return 1
    fi

    if ! yq --version >/dev/null 2>&1; then
        echo "❌ ERROR: yq instalado no funciona correctamente" >&2
        echo "Por favor reinstala yq-go" >&2
        return 1
    fi

    return 0
}

# === Funciones Wrapper para Snap ===
# Cuando yq se instala con Snap, tiene restricciones de acceso a archivos
# Workaround: usar stdin en lugar de pasar el archivo como argumento

# Leer de un archivo YAML (compatible con Snap)
yq_read() {
    local query="$1"
    local file="$2"

    # Usar stdin para evitar restricciones de Snap
    yq eval "$query" < "$file"
}

# Escribir a un archivo YAML in-place (compatible con Snap)
yq_write() {
    local query="$1"
    local file="$2"

    # Usar stdin/stdout para evitar restricciones de Snap
    local temp_file="${file}.tmp"
    yq eval "$query" < "$file" > "$temp_file" && mv "$temp_file" "$file"
}

# Exportar funciones para uso en otros scripts
export -f yq_read
export -f yq_write

# Ejecutar verificación al cargar el script
if ! _verify_yq_go; then
    # El script falla si yq no está correctamente instalado
    return 1 2>/dev/null || exit 1
fi
