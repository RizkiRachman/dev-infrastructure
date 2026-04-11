#!/bin/bash
# Stop all infrastructure services (suspend — all data and config preserved)
# Restarts cleanly with: ./commands/start-all.sh
# To wipe everything:    ./commands/reset-all.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

show_help() {
    echo "Stop All Infrastructure Services"
    echo ""
    echo "Usage: ./commands/stop-all.sh [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Suspends all services without deleting any data or config:"
    echo "  - Kills Tekton dashboard port-forward"
    echo "  - Stops Docker containers (state preserved, restart with start-all.sh)"
    echo "  - Stops k3d cluster (all K8s resources preserved)"
    echo ""
    echo "To wipe everything: ./commands/reset-all.sh"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

echo "🛑 Stopping all infrastructure services (data preserved)..."
echo ""

STEP=1
TOTAL_STEPS=3

# Step 1: Stop Tekton dashboard port-forward
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Stopping Tekton dashboard port-forward..."
"$ROOT_DIR/services/tekton/scripts/stop.sh"
STEP=$((STEP + 1))
echo ""

# Step 2: Stop Docker containers (preserve volumes/state)
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Stopping Docker containers (state preserved)..."
cd "$ROOT_DIR/orchestration"
if docker-compose stop 2>&1; then
    echo -e "${GREEN}✓${NC} Docker containers stopped"
else
    echo -e "${YELLOW}→${NC} Some containers may already be stopped"
fi
STEP=$((STEP + 1))
echo ""

# Step 3: Stop k3d cluster (preserve all K8s resources and configs)
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Stopping k3d cluster (K8s resources preserved)..."
CLUSTER_NAME="${CLUSTER_NAME:-dev-infra}"
if command -v k3d &>/dev/null && k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    k3d cluster stop "${CLUSTER_NAME}"
    echo -e "${GREEN}✓${NC} k3d cluster stopped"
else
    echo -e "${YELLOW}→${NC} No running k3d cluster found"
fi
echo ""

echo "================================="
echo -e "${GREEN}✅ All services stopped!${NC}"
echo "================================="
echo ""
echo "All data and configuration preserved."
echo "  Restart: ./commands/start-all.sh"
echo "  Wipe:    ./commands/reset-all.sh"
echo ""
