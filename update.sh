#!/usr/bin/env bash
# HMS updater wrapper - delegates to commands/self-update
# Kept for direct execution compatibility: ./update.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_CMD="$SCRIPT_DIR/hms/bin/commands/self-update"

# Verify the update command exists
if [ ! -f "$UPDATE_CMD" ]; then
    echo "❌ Update command not found: $UPDATE_CMD"
    exit 1
fi

# Delegate to the update command, forwarding all arguments
exec "$UPDATE_CMD" "$@"
