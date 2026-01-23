#!/usr/bin/env bash
# Script de validación de la refactorización
# Verifica que todos los archivos estén en su lugar

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 Validando refactorización del contenedor HMS..."
echo ""

ERRORS=0
WARNINGS=0

check_file() {
    local file="$1"
    local desc="$2"

    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $desc"
    else
        echo -e "${RED}✗${NC} $desc - FALTA"
        ((ERRORS++))
    fi
}

check_executable() {
    local file="$1"
    local desc="$2"

    if [ -f "$file" ]; then
        if [ -x "$file" ]; then
            echo -e "${GREEN}✓${NC} $desc (ejecutable)"
        else
            echo -e "${YELLOW}⚠${NC} $desc (no ejecutable)"
            ((WARNINGS++))
        fi
    else
        echo -e "${RED}✗${NC} $desc - FALTA"
        ((ERRORS++))
    fi
}

check_not_exists() {
    local file="$1"
    local desc="$2"

    if [ ! -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $desc (eliminado correctamente)"
    else
        echo -e "${YELLOW}⚠${NC} $desc (debería estar eliminado)"
        ((WARNINGS++))
    fi
}

echo "Archivos de configuración:"
check_file "$REPO_ROOT/config.default.toml" "config.default.toml"
check_file "$REPO_ROOT/config.toml" "config.toml"
check_not_exists "$REPO_ROOT/core/hms/.env" ".env antiguo"

echo ""
echo "Scripts de instalación:"
check_executable "$REPO_ROOT/install.sh" "install.sh"
check_executable "$REPO_ROOT/hms/bin/hms" "hms wrapper"

echo ""
echo "Comandos bash puros:"
check_executable "$REPO_ROOT/commands/start" "commands/start"
check_executable "$REPO_ROOT/commands/stop" "commands/stop"

echo ""
echo "Entrypoint del contenedor:"
check_executable "$REPO_ROOT/core/hms/entrypoint.sh" "entrypoint.sh"

echo ""
echo "Archivos Docker:"
check_file "$REPO_ROOT/core/hms/Dockerfile" "Dockerfile"
check_file "$REPO_ROOT/core/hms/docker-compose.yml" "docker-compose.yml"

echo ""
echo "Plugins Python:"
check_file "$REPO_ROOT/hms/plugins/global/start.py" "start.py plugin"
check_file "$REPO_ROOT/hms/plugins/global/stop.py" "stop.py plugin"

echo ""
echo "Documentación:"
check_file "$REPO_ROOT/docs/REFACTORING-CONTAINER.md" "Documentación de refactorización"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✅ Validación completa: Todo correcto${NC}"
    else
        echo -e "${YELLOW}⚠️  Validación con advertencias: $WARNINGS warning(s)${NC}"
    fi
    echo ""
    echo "Siguiente paso: Inicia Docker Desktop y ejecuta:"
    echo "  hms start"
    exit 0
else
    echo -e "${RED}❌ Validación fallida: $ERRORS error(es), $WARNINGS warning(s)${NC}"
    exit 1
fi

