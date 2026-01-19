#!/bin/bash

# Script de pre-deploy para el stack media
# Genera docker-compose.override.yml basado en configuración de hardware
# Se ejecuta automáticamente antes del deploy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$SCRIPT_DIR"
STACK_NAME="$(basename "$STACK_DIR")"
OVERRIDE_FILE="$STACK_DIR/docker-compose.override.yml"

# Cargar variables de entorno del stack (si existen)
if [[ -f "$STACK_DIR/.env" ]]; then
    set -a
    source "$STACK_DIR/.env"
    set +a
fi

echo "🔧 Generando configuración de hardware para stack: $STACK_NAME"

# Generar override file
cat > "$OVERRIDE_FILE" << 'EOF'

services:
EOF

# Configurar Tdarr según hardware
if [[ "${ENABLE_INTEL_QSV:-false}" == "true" ]]; then
    echo "    devices:" >> "$OVERRIDE_FILE"
    echo "      - /dev/dri:/dev/dri" >> "$OVERRIDE_FILE"
    echo "    # Intel Quick Sync habilitado para Tdarr" >> "$OVERRIDE_FILE"
elif [[ "${ENABLE_NVIDIA:-false}" == "true" ]]; then
    echo "    runtime: nvidia" >> "$OVERRIDE_FILE"
    echo "    environment:" >> "$OVERRIDE_FILE"
    echo "      - NVIDIA_VISIBLE_DEVICES=all" >> "$OVERRIDE_FILE"
    echo "      - NVIDIA_DRIVER_CAPABILITIES=compute,video,utility" >> "$OVERRIDE_FILE"
    echo "    # NVIDIA NVENC habilitado para Tdarr" >> "$OVERRIDE_FILE"
elif [[ "${ENABLE_VAAPI:-false}" == "true" ]]; then
    echo "    devices:" >> "$OVERRIDE_FILE"
    echo "      - /dev/dri:/dev/dri" >> "$OVERRIDE_FILE"
    echo "    # VAAPI habilitado para Tdarr" >> "$OVERRIDE_FILE"
else
    echo "    {} # Sin aceleración por hardware para Tdarr" >> "$OVERRIDE_FILE"
fi

echo "✅ Configuración de hardware generada: $OVERRIDE_FILE"
echo "📋 Configuración aplicada:"
if [[ "${ENABLE_INTEL_QSV:-false}" == "true" ]]; then
    echo "   🔧 Tdarr: Intel Quick Sync Video habilitado para transcodificación"
elif [[ "${ENABLE_NVIDIA:-false}" == "true" ]]; then
    echo "   🔧 Tdarr: NVIDIA NVENC habilitado para transcodificación"
elif [[ "${ENABLE_VAAPI:-false}" == "true" ]]; then
    echo "   🔧 Tdarr: VAAPI habilitado para transcodificación"
else
    echo "   💻 Tdarr: Solo CPU para transcodificación"
fi
