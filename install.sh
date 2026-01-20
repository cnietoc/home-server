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

# Validar permisos de Docker
HOST_OS=$(uname -s)
if [ "$HOST_OS" = "Darwin" ]; then
    echo "ℹ️ macOS detectado: Docker Desktop no usa el grupo 'docker' del host"
    echo "   Se omitirá la verificación de grupo"
else
    echo ""
    echo "🔐 Validando permisos de Docker..."
    if ! groups | grep -q docker; then
        echo -e "${YELLOW}⚠️  Tu usuario no está en el grupo 'docker'${NC}"
        echo ""
        echo "Para agregar tu usuario al grupo docker ejecuta:"
        echo "    sudo usermod -aG docker $USER"
        echo ""
        echo "Luego cierra sesión y vuelve a iniciar sesión para aplicar los cambios."
        echo ""
        read -p "¿Continuar de todas formas? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo -e "${GREEN}✅ Usuario en grupo docker${NC}"
    fi
fi

# Generar .env con PUID/PGID dinámicos
echo ""
echo "📝 Generando archivo .env para HMS..."
ENV_FILE="$COMPOSE_DIR/.env"
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Detectar timezone del sistema
if [ -f /etc/timezone ]; then
    SYSTEM_TZ=$(cat /etc/timezone)
elif [ -L /etc/localtime ]; then
    SYSTEM_TZ=$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')
else
    SYSTEM_TZ="UTC"
fi

cat > "$ENV_FILE" << EOF
# Archivo generado automáticamente por install.sh
# Variables del sistema
PUID=$CURRENT_UID
PGID=$CURRENT_GID
TZ=$SYSTEM_TZ
EOF

echo -e "${GREEN}✅ .env generado con PUID=$CURRENT_UID, PGID=$CURRENT_GID, TZ=$SYSTEM_TZ${NC}"

# Ajustar permisos de directorios de datos si existen
for dir in "$REPO_ROOT/data" "$REPO_ROOT/logs"; do
    if [ -d "$dir" ]; then
        echo "🔧 Ajustando permisos de $dir..."
        if [ -w "$dir" ]; then
            chown -R "$CURRENT_UID:$CURRENT_GID" "$dir" 2>/dev/null || {
                echo -e "${YELLOW}⚠️  No se pudieron cambiar todos los permisos en $dir (algunos archivos pueden ser de root)${NC}"
            }
        fi
    fi
done

# Levantar contenedor HMS
echo ""
echo "📦 Levantando contenedor HMS..."
(cd "$COMPOSE_DIR" && docker compose up -d --build)
sleep 2

# Verificar contenedor corriendo
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${GREEN}✅ Contenedor HMS corriendo${NC}"
else
    echo -e "${RED}❌ El contenedor HMS no está corriendo${NC}"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
    exit 1
fi

# Probar CLI dentro del contenedor
echo ""
echo "🔍 Probando CLI HMS..."
if docker exec "$CONTAINER_NAME" python -m hms --help >/dev/null 2>&1; then
    echo -e "${GREEN}✅ CLI HMS OK${NC}"
else
    echo -e "${RED}❌ Error al ejecutar CLI HMS${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Instalación completada${NC}"
echo ""
echo "Prueba con:"
echo "    hms --help"
echo "    hms show stacks"
