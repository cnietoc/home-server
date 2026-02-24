#!/usr/bin/env bash
# HMS installer wrapper - ejecuta el comando install desde commands/
# Este script se mantiene para compatibilidad de ejecución directa: ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_CMD="$SCRIPT_DIR/hms/bin/commands/install"

# Verificar que existe el comando install
if [ ! -f "$INSTALL_CMD" ]; then
    echo "❌ No se encontró $INSTALL_CMD"
    exit 1
fi

# Delegar la ejecución al comando install, pasando todos los argumentos
exec "$INSTALL_CMD" "$@"
