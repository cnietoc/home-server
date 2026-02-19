#!/usr/bin/env bash
# HMS updater wrapper - ejecuta el comando update desde commands/
# Este script se mantiene para compatibilidad de ejecución directa: ./update.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_CMD="$SCRIPT_DIR/hms/bin/commands/update"

# Verificar que existe el comando update
if [ ! -f "$UPDATE_CMD" ]; then
    echo "❌ No se encontró $UPDATE_CMD"
    exit 1
fi

# Delegar la ejecución al comando update, pasando todos los argumentos
exec "$UPDATE_CMD" "$@"

