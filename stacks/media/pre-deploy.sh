#!/bin/bash

# Pre-deploy script for the media stack
# Generates docker-compose.override.yml based on hardware configuration
# Runs automatically before deploy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$SCRIPT_DIR"
STACK_NAME="$(basename "$STACK_DIR")"
OVERRIDE_FILE="$STACK_DIR/docker-compose.override.yml"

# Load stack environment variables (if present)
if [[ -f "$STACK_DIR/.env" ]]; then
    set -a
    source "$STACK_DIR/.env"
    set +a
fi

echo "🔧 Generating hardware configuration for stack: $STACK_NAME"

# Generate override file
cat > "$OVERRIDE_FILE" << 'EOF'

services:
EOF

# Configure Tdarr based on available hardware
if [[ "${ENABLE_INTEL_QSV}" == "true" ]]; then
    echo "    devices:" >> "$OVERRIDE_FILE"
    echo "      - /dev/dri:/dev/dri" >> "$OVERRIDE_FILE"
    echo "    # Intel Quick Sync enabled for Tdarr" >> "$OVERRIDE_FILE"
elif [[ "${ENABLE_NVIDIA}" == "true" ]]; then
    echo "    runtime: nvidia" >> "$OVERRIDE_FILE"
    echo "    environment:" >> "$OVERRIDE_FILE"
    echo "      - NVIDIA_VISIBLE_DEVICES=all" >> "$OVERRIDE_FILE"
    echo "      - NVIDIA_DRIVER_CAPABILITIES=compute,video,utility" >> "$OVERRIDE_FILE"
    echo "    # NVIDIA NVENC enabled for Tdarr" >> "$OVERRIDE_FILE"
elif [[ "${ENABLE_VAAPI}" == "true" ]]; then
    echo "    devices:" >> "$OVERRIDE_FILE"
    echo "      - /dev/dri:/dev/dri" >> "$OVERRIDE_FILE"
    echo "    # VAAPI enabled for Tdarr" >> "$OVERRIDE_FILE"
else
    echo "    {} # No hardware acceleration for Tdarr" >> "$OVERRIDE_FILE"
fi

# Remove stale qBittorrent lockfile left by unclean shutdowns (e.g. hard power-off)
QBIT_LOCK="${STACK_DATA}/config/qbittorrent/config/lockfile"
QBIT_SOCK="${STACK_DATA}/config/qbittorrent/config/ipc-socket"
if [[ -f "$QBIT_LOCK" ]]; then
    echo "🧹 Removing stale qBittorrent lockfile"
    rm -f "$QBIT_LOCK" "$QBIT_SOCK"
fi

echo "✅ Hardware configuration generated: $OVERRIDE_FILE"
echo "📋 Applied configuration:"
if [[ "${ENABLE_INTEL_QSV}" == "true" ]]; then
    echo "   🔧 Tdarr: Intel Quick Sync Video enabled for transcoding"
elif [[ "${ENABLE_NVIDIA}" == "true" ]]; then
    echo "   🔧 Tdarr: NVIDIA NVENC enabled for transcoding"
elif [[ "${ENABLE_VAAPI}" == "true" ]]; then
    echo "   🔧 Tdarr: VAAPI enabled for transcoding"
else
    echo "   💻 Tdarr: CPU-only transcoding"
fi
