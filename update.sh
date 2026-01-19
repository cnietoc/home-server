#!/usr/bin/env bash
# HMS updater - pull del repo y rebuild del contenedor si hay cambios
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
COMPOSE_DIR="$REPO_ROOT/docker/hms"
CONTAINER_NAME="hms"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 HMS Updater${NC}"
echo ""

# Validar que estamos en el repo correcto
if [ ! -d "$REPO_ROOT/.git" ]; then
    echo -e "${RED}❌ No se encontró .git en $REPO_ROOT${NC}"
    exit 1
fi

# Validar Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker no está instalado en el host${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker daemon no disponible. Continuando sin rebuild...${NC}"
    SKIP_REBUILD=1
else
    SKIP_REBUILD=0
fi

# Validar compose
if [ ! -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    echo -e "${RED}❌ No se encontró docker-compose en: $COMPOSE_DIR/docker-compose.yml${NC}"
    exit 1
fi

# Guardar hash antes de pull
echo "📊 Comparando cambios..."
HASH_BEFORE=$(git -C "$REPO_ROOT" rev-parse HEAD)

# Git pull
echo "⬇️  Haciendo git pull..."
if ! git -C "$REPO_ROOT" pull; then
    echo -e "${RED}❌ Error en git pull. Verifica conflictos manualmente.${NC}"
    exit 1
fi

HASH_AFTER=$(git -C "$REPO_ROOT" rev-parse HEAD)

# Si el hash no cambió, nada que hacer
if [ "$HASH_BEFORE" = "$HASH_AFTER" ]; then
    echo -e "${YELLOW}ℹ️  El repositorio ya estaba actualizado; se reconstruirá igualmente${NC}"
fi

# Detectar cambios relevantes
CHANGED_FILES=$(git -C "$REPO_ROOT" diff --name-only $HASH_BEFORE..$HASH_AFTER)

if echo "$CHANGED_FILES" | grep -qE '^hms/|^docker/hms/|^pyproject\.toml|^requirements\.txt'; then
    echo -e "${YELLOW}📝 Cambios detectados en:${NC}"
    echo "$CHANGED_FILES" | grep -E '^hms/|^docker/hms/|^pyproject\.toml|^requirements\.txt' || true
else
    echo -e "${GREEN}ℹ️  Sin cambios relevantes en el código HMS${NC}"
fi

# Si Docker no está disponible, no rebuildar
if [ $SKIP_REBUILD -eq 1 ]; then
    echo -e "${YELLOW}⚠️  Docker no disponible. Cambios traídos pero no reconstruidos.${NC}"
    exit 0
fi

# Rebuildar el contenedor
echo ""
echo -e "${BLUE}🔨 Reconstruyendo imagen Docker...${NC}"

# Parar y eliminar contenedor anterior
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "🛑 Parando contenedor $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME" || true
    sleep 1
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "🗑️  Eliminando contenedor $CONTAINER_NAME..."
    docker rm "$CONTAINER_NAME" || true
fi

# Rebuildar imagen (sin caché para asegurar que es nueva)
echo "📦 Construyendo nueva imagen..."
(cd "$COMPOSE_DIR" && docker compose build)

# Levantar contenedor
echo "🚀 Levantando nuevo contenedor..."
(cd "$COMPOSE_DIR" && docker compose up -d)
sleep 2

# Verificar que el contenedor está corriendo
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${GREEN}✅ Contenedor HMS actualizado y corriendo${NC}"
else
    echo -e "${RED}❌ Error: El contenedor HMS no está corriendo${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Actualización completada${NC}"
echo -e "${GREEN}Cambios aplicados:${NC}"
echo "$CHANGED_FILES"

