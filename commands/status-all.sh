#!/bin/bash
# Check status of all infrastructure services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Help function
show_help() {
    echo "Check Status of All Infrastructure Services"
    echo ""
    echo "Usage: ./commands/status-all.sh [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "This script checks status of:"
    echo "  - Docker Compose services (Vault, PostgreSQL, Gravitee)"
    echo "  - k3d cluster (includes built-in registry)"
    echo "  - Tekton infrastructure (Pipelines, Dashboard)"
    echo "  - Kubernetes cluster connection"
    echo ""
}

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

echo "📊 Status of all infrastructure services"
echo "========================================"
echo ""

# Check Docker containers
echo -e "${BLUE}[1/4]${NC} Docker Compose Services:"
cd "$ROOT_DIR/orchestration"
docker-compose ps
echo ""

# Check Tekton status
echo -e "${BLUE}[2/4]${NC} Tekton Infrastructure:"
"$ROOT_DIR/services/tekton/scripts/status.sh"
echo ""

# Check k3d cluster & registry
echo -e "${BLUE}[3/4]${NC} k3d Cluster & Registry:"
CLUSTER_NAME="${CLUSTER_NAME:-dev-infra}"
if command -v k3d &>/dev/null && k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo -e "   ${GREEN}✅ k3d cluster running${NC}"
    REGISTRY_PORT=$(grep '^REGISTRY_PORT' "$ROOT_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "5002")
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${REGISTRY_PORT:-5002}/v2/" | grep -q "200"; then
        echo -e "   ${GREEN}✅ Registry reachable${NC} at localhost:${REGISTRY_PORT:-5002}"
    else
        echo -e "   ${YELLOW}⚠️  Registry not reachable${NC}"
    fi
else
    echo -e "   ${RED}❌ k3d cluster not running${NC}"
fi
echo ""

# Check Kubernetes connection
echo -e "${BLUE}[4/4]${NC} Kubernetes Cluster:"
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✅ Connected${NC}"
    kubectl get nodes
else
    echo -e "${YELLOW}⚠️  Not connected${NC}"
fi
echo ""
