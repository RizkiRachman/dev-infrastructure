#!/bin/bash
# Stop all dev infrastructure services (data and config preserved)
# Use --reset to also remove volumes (wipe data)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

RESET=false
if [ "$1" = "--reset" ]; then
    RESET=true
fi

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

echo -e "${RED}🛑 Stopping Dev Infrastructure...${NC}"
echo "=================================="
echo ""

# 1. Kill Tekton dashboard port-forward
TEKTON_DASHBOARD_PID="$ROOT_DIR/logs/tekton-dashboard.pid"
if [ -f "$TEKTON_DASHBOARD_PID" ]; then
    PID=$(cat "$TEKTON_DASHBOARD_PID" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" > /dev/null 2>&1 || true
        printf "   %-30s${GREEN}✓ stopped${NC}\n" "tekton-dashboard port-forward"
    fi
    rm -f "$TEKTON_DASHBOARD_PID"
fi

# 2. Stop containers gracefully (state preserved for restart)
echo -e "${BLUE}🔧 Stopping containers...${NC}"
cd "$ROOT_DIR/orchestration"
if [ "$RESET" = true ]; then
    docker-compose down -v --remove-orphans > /dev/null 2>&1 || true
    echo -e "   ${YELLOW}✓${NC} Containers and volumes removed"
else
    docker-compose stop > /dev/null 2>&1 || true
    echo -e "   ${GREEN}✓${NC} Containers stopped (volumes/state preserved)"
fi

echo ""
if [ "$RESET" = true ]; then
    echo -e "${GREEN}✅ All services stopped and data wiped.${NC}"
    echo -e "   To also reset k3d: ${YELLOW}./commands/reset-all.sh${NC}"
else
    echo -e "${GREEN}✅ All services stopped. Data preserved.${NC}"
    echo -e "   Restart: ${YELLOW}./commands/start-all.sh${NC}"
    echo -e "   Wipe:    ${YELLOW}./stop.sh --reset${NC} or ${YELLOW}./commands/reset-all.sh${NC}"
fi
