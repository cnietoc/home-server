#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'

confirm() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    read -r -p "   ¿Continuar? [s/N] " ans
    [[ "${ans,,}" == "s" ]]
}

echo -e "${BOLD}🧹 Docker Clean${NC}"
echo ""

# ── Parar todos los contenedores corriendo ───────────────────────────────────
running=$(docker ps -q)
if [[ -n "$running" ]]; then
    count=$(echo "$running" | wc -l | tr -d ' ')
    confirm "Se van a parar $count contenedor(es) en ejecución" || { echo "Cancelado."; exit 0; }
    docker stop $running
    echo -e "${GREEN}✓ Contenedores parados${NC}"
else
    echo "  Sin contenedores en ejecución"
fi

echo ""

# ── Contenedores parados ──────────────────────────────────────────────────────
docker container prune -f
echo -e "${GREEN}✓ Contenedores parados eliminados${NC}"

# ── Imágenes sin usar ─────────────────────────────────────────────────────────
docker image prune -af
echo -e "${GREEN}✓ Imágenes eliminadas${NC}"

# ── Volúmenes sin usar ────────────────────────────────────────────────────────
docker volume prune -f
echo -e "${GREEN}✓ Volúmenes eliminados${NC}"

# ── Redes sin usar ────────────────────────────────────────────────────────────
docker network prune -f
echo -e "${GREEN}✓ Redes eliminadas${NC}"

# ── Build cache ───────────────────────────────────────────────────────────────
docker buildx prune -af
echo -e "${GREEN}✓ Build cache eliminada${NC}"

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}📊 Estado final:${NC}"
docker system df
