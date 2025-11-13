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

# Ejecutar verificación al cargar el script
if ! _verify_yq_go; then
    # El script falla si yq no está correctamente instalado
    return 1 2>/dev/null || exit 1
fi
