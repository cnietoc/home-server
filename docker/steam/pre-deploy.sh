#!/bin/bash

# Script de pre-deploy para el stack steam
# Genera ASF.json y DefaultBot.json basados en variables de entorno

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$SCRIPT_DIR"
CONFIG_DIR="$SCRIPT_DIR/config"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Cargar librería de logs
source "$PROJECT_ROOT/lib/logs.sh"

# Crear directorio de config si no existe
mkdir -p "$CONFIG_DIR"

# Cargar variables de entorno del stack
if [[ -f "$STACK_DIR/.env" ]]; then
    set -a  # automatically export all variables
    source "$STACK_DIR/.env"
    set +a  # turn off automatic export
fi

logs::info "🔧 Generando configuración de ASF"

# Generar ASF.json usando envsubst
logs::info "📝 Generando ASF.json..."
envsubst < "$SCRIPT_DIR/ASF.json" > "$CONFIG_DIR/ASF.json"
logs::info "✅ ASF.json generado"

# Generar DefaultBot.json usando envsubst
logs::info "📝 Generando DefaultBot.json..."
envsubst < "$SCRIPT_DIR/DefaultBot.json" > "$CONFIG_DIR/DefaultBot.json"
logs::info "✅ DefaultBot.json generado"

logs::info "✅ Pre-deploy completado"
