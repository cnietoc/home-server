#!/usr/bin/env bash
# HMS uninstaller wrapper - delegates to commands/uninstall
# Kept for direct execution compatibility: ./uninstall.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNINSTALL_CMD="$SCRIPT_DIR/hms/bin/commands/uninstall"

# Verify the uninstall command exists
if [ ! -f "$UNINSTALL_CMD" ]; then
    echo "❌ Uninstall command not found: $UNINSTALL_CMD"
    exit 1
fi

# Delegate to the uninstall command, forwarding all arguments
exec "$UNINSTALL_CMD" "$@"
