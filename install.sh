#!/usr/bin/env bash
# HMS installer wrapper - delegates to commands/install
# Kept for direct execution compatibility: ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_CMD="$SCRIPT_DIR/hms/bin/commands/install"

# Verify the install command exists
if [ ! -f "$INSTALL_CMD" ]; then
    echo "❌ Install command not found: $INSTALL_CMD"
    exit 1
fi

# Delegate to the install command, forwarding all arguments
exec "$INSTALL_CMD" "$@"
