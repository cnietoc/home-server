#!/usr/bin/env bash
# HMS uninstaller - elimina symlink y para/baja contenedor (best-effort)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
USER_BIN="$HOME/.local/bin"
TARGET="$USER_BIN/hms"
COMPOSE_DIR="$REPO_ROOT/docker/hms"
CONTAINER_NAME="hms"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🗑️  Desinstalador HMS"
echo ""

# Eliminar symlink (best-effort)
if [ -L "$TARGET" ]; then
    rm -f "$TARGET"
    echo -e "${GREEN}✅ Symlink eliminado: $TARGET${NC}"
elif [ -e "$TARGET" ]; then
    echo -e "${YELLOW}⚠️  $TARGET existe pero no es symlink. No se elimina automáticamente.${NC}"
else
    echo -e "${YELLOW}ℹ️  No existe symlink en $TARGET${NC}"
fi

# Best-effort: parar contenedor
if command -v docker &> /dev/null; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" 2>/dev/null; then
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        echo -e "${GREEN}✅ Contenedor parado${NC}"

        # Intentar remover contenedor
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        echo -e "${GREEN}✅ Contenedor eliminado${NC}"
    else
        echo -e "${YELLOW}ℹ️  Contenedor $CONTAINER_NAME no está corriendo${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Docker no disponible; no se para el contenedor${NC}"
fi

# Best-effort: docker compose down
if [ -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    (cd "$COMPOSE_DIR" && docker compose down 2>/dev/null) || true
    echo -e "${GREEN}✅ Stack HMS bajado (docker compose down)${NC}"
fi

echo ""
echo -e "${GREEN}✅ Desinstalación completada (best-effort)${NC}"

