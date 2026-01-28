#!/usr/bin/env bash
# HMS uninstaller wrapper - ejecuta el comando uninstall desde commands/
# Este script se mantiene para compatibilidad de ejecución directa: ./uninstall.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNINSTALL_CMD="$SCRIPT_DIR/commands/uninstall"

# Verificar que existe el comando uninstall
if [ ! -f "$UNINSTALL_CMD" ]; then
    echo "❌ No se encontró $UNINSTALL_CMD"
    exit 1
fi

# Delegar la ejecución al comando uninstall, pasando todos los argumentos
exec "$UNINSTALL_CMD" "$@"

