#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'

confirm() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    read -r -p "   ¿Continuar? [s/N] " ans
    [[ "${ans,,}" == "s" ]]
}

usage() {
    echo -e "${BOLD}Uso:${NC} $0 [--all]"
    echo ""
    echo "  (sin flags)   Limpia recursos no usados (contenedores parados, imágenes"
    echo "                sin usar, volúmenes y redes huérfanos, build cache)"
    echo "  --all         Para todos los contenedores en ejecución y luego limpia todo"
    exit 1
}

FULL=0
for arg in "$@"; do
    case "$arg" in
        --all) FULL=1 ;;
        -h|--help) usage ;;
        *) echo -e "${RED}Argumento desconocido: $arg${NC}"; usage ;;
    esac
done

if [[ $FULL -eq 1 ]]; then
    echo -e "${BOLD}🧹 Docker Clean (todo)${NC}"
else
    echo -e "${BOLD}🧹 Docker Clean${NC}"
fi
echo ""

# ── Parar contenedores (solo en modo --all) ───────────────────────────────────
if [[ $FULL -eq 1 ]]; then
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
fi

# ── Contenedores parados ──────────────────────────────────────────────────────
docker container prune -f
echo -e "${GREEN}✓ Contenedores parados eliminados${NC}"

# ── Imágenes sin usar ─────────────────────────────────────────────────────────
if [[ $FULL -eq 1 ]]; then
    docker image prune -af
    echo -e "${GREEN}✓ Imágenes eliminadas (todas)${NC}"
else
    docker image prune -f
    echo -e "${GREEN}✓ Imágenes huérfanas eliminadas${NC}"
fi

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
