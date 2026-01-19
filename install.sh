#!/usr/bin/env bash
# HMS installer - crea symlink en ~/.local/bin/hms y levanta el contenedor
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
USER_BIN="$HOME/.local/bin"
WRAPPER_SRC="$REPO_ROOT/hms/bin/hms"
COMPOSE_DIR="$REPO_ROOT/docker/hms"
CONTAINER_NAME="hms"
FORCE="${1:---force}"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🚀 Instalador HMS"
echo ""

# Validar Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker no está instalado en el host${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker daemon no disponible. Abre Docker Desktop e inténtalo de nuevo.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker disponible${NC}"

# Validar compose
if [ ! -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    echo -e "${RED}❌ No se encontró docker-compose en: $COMPOSE_DIR/docker-compose.yml${NC}"
    exit 1
fi
echo -e "${GREEN}✅ docker-compose.yml encontrado${NC}"

# Validar wrapper fuente
if [ ! -f "$WRAPPER_SRC" ]; then
    echo -e "${RED}❌ No se encontró wrapper fuente en: $WRAPPER_SRC${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Wrapper fuente encontrado${NC}"

# Crear ~/.local/bin si no existe
mkdir -p "$USER_BIN"
echo -e "${GREEN}✅ ~/.local/bin listo${NC}"

# Verificar si el symlink ya existe
TARGET="$USER_BIN/hms"
if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    if [ "$FORCE" != "--force" ]; then
        echo -e "${RED}❌ $TARGET ya existe. Usa --force para sobrescribir.${NC}"
        exit 1
    fi
    rm -f "$TARGET"
    echo "⚠️  Symlink anterior eliminado"
fi

# Crear symlink
ln -s "$WRAPPER_SRC" "$TARGET"
echo -e "${GREEN}✅ Symlink creado: $TARGET -> $WRAPPER_SRC${NC}"

# Verificar PATH contiene ~/.local/bin
if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
    echo -e "${YELLOW}❌ ~/.local/bin no está en PATH${NC}"
    echo ""
    echo "Añade esta línea a tu ~/.zshrc:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    echo "Luego ejecuta:"
    echo "    source ~/.zshrc"
    exit 1
fi
echo -e "${GREEN}✅ ~/.local/bin está en PATH${NC}"

# Levantar contenedor
echo ""
echo "📦 Levantando contenedor HMS..."
(cd "$COMPOSE_DIR" && docker compose up -d)
sleep 2

# Verificar contenedor corriendo
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${GREEN}✅ Contenedor HMS corriendo${NC}"
else
    echo -e "${RED}❌ El contenedor HMS no parece estar corriendo${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Instalación completada${NC}"
echo ""
echo "Prueba con:"
echo "    hms --help"
echo "    hms show stacks"
