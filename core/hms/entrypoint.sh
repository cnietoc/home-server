#!/usr/bin/env bash
# HMS container entrypoint
# Reads config.toml and sets environment variables

set -euo pipefail

CONFIG_FILE="/app/config.toml"

# Function to parse TOML using yq
get_toml_value() {
    local file="$1"
    local path="$2"

    if [ -f "$file" ]; then
        yq eval "$path" "$file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Read values from config.toml
if [ -f "$CONFIG_FILE" ]; then
    PUID=$(get_toml_value "$CONFIG_FILE" ".global.puid")
    PGID=$(get_toml_value "$CONFIG_FILE" ".global.pgid")
else
    echo "⚠️ config.toml not found at $CONFIG_FILE"
    PUID=""
    PGID=""
fi

# If the puid/pgid in config don't match the container UID/GID, fail with a helpful message
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
if [[ -n "$PUID" && "$PUID" != "$CURRENT_UID" ]]; then
    echo "❌ PUID in config.toml ($PUID) does not match the container UID ($CURRENT_UID)."
    echo "   Please run \"hms start\" to recreate the container with the correct PUID."
    exit 1
fi

if [[ -n "$PGID" && "$PGID" != "$CURRENT_GID" ]]; then
    echo "❌ PGID in config.toml ($PGID) does not match the container GID ($CURRENT_GID)."
    echo "   Please run \"hms start\" to recreate the container with the correct PGID."
    exit 1
fi

exec "$@"
