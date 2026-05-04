#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'

confirm() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    read -r -p "   Continue? [y/N] " ans
    [[ "${ans,,}" == "y" ]]
}

usage() {
    echo -e "${BOLD}Usage:${NC} $0 [--all]"
    echo ""
    echo "  (no flags)    Cleans unused resources (stopped containers, dangling images,"
    echo "                unused volumes and networks, build cache)"
    echo "  --all         Stop all running containers then clean everything"
    exit 1
}

FULL=0
for arg in "$@"; do
    case "$arg" in
        --all) FULL=1 ;;
        -h|--help) usage ;;
        *) echo -e "${RED}Unknown argument: $arg${NC}"; usage ;;
    esac
done

if [[ $FULL -eq 1 ]]; then
    echo -e "${BOLD}🧹 Docker Clean (all)${NC}"
else
    echo -e "${BOLD}🧹 Docker Clean${NC}"
fi
echo ""

# ── Stop containers (--all mode only) ────────────────────────────────────────
if [[ $FULL -eq 1 ]]; then
    running=$(docker ps -q)
    if [[ -n "$running" ]]; then
        count=$(echo "$running" | wc -l | tr -d ' ')
        confirm "About to stop $count running container(s)" || { echo "Cancelled."; exit 0; }
        docker stop $running
        echo -e "${GREEN}✓ Containers stopped${NC}"
    else
        echo "  No running containers"
    fi
    echo ""
fi

# ── Stopped containers ────────────────────────────────────────────────────────
docker container prune -f
echo -e "${GREEN}✓ Stopped containers removed${NC}"

# ── Unused images ─────────────────────────────────────────────────────────────
if [[ $FULL -eq 1 ]]; then
    docker image prune -af
    echo -e "${GREEN}✓ All images removed${NC}"
else
    docker image prune -f
    echo -e "${GREEN}✓ Dangling images removed${NC}"
fi

# ── Unused volumes ────────────────────────────────────────────────────────────
docker volume prune -f
echo -e "${GREEN}✓ Volumes removed${NC}"

# ── Unused networks ───────────────────────────────────────────────────────────
docker network prune -f
echo -e "${GREEN}✓ Networks removed${NC}"

# ── Build cache ───────────────────────────────────────────────────────────────
docker buildx prune -af
echo -e "${GREEN}✓ Build cache cleared${NC}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}📊 Final state:${NC}"
docker system df
