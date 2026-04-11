#!/bin/bash
# Reset all infrastructure — deletes all resources, namespaces, volumes, and the cluster.
# Use this to start completely fresh.
# For a simple suspend (data preserved): ./commands/stop-all.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

show_help() {
    echo "Reset All Infrastructure (Full Wipe)"
    echo ""
    echo "Usage: ./commands/reset-all.sh [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -y, --yes               Skip confirmation prompt"
    echo "  --wipe-postgres         Delete PostgreSQL data volume (default: preserved)"
    echo ""
    echo "Deletes everything:"
    echo "  - Tekton kubectl proxy + all Kubernetes namespaces"
    echo "  - Docker containers and volumes (postgres-data preserved by default)"
    echo "  - k3d cluster and built-in registry"
    echo ""
    echo "To just suspend (data preserved): ./commands/stop-all.sh"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

PRESERVE_POSTGRES=true
SKIP_CONFIRM=false

for arg in "$@"; do
    case $arg in
        --wipe-postgres)
            PRESERVE_POSTGRES=false
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

PIPELINE_NAMESPACE="${PIPELINE_NAMESPACE:-tekton-pipelines}"
TEKTON_NAMESPACE="${TEKTON_NAMESPACE:-tekton-pipelines}"
CLUSTER_NAME="${CLUSTER_NAME:-dev-infra}"
LOG_DIR="$ROOT_DIR/logs"

echo -e "${RED}⚠️  RESET: This will delete all resources, volumes, and the cluster.${NC}"
echo ""

# Confirmation (skip with -y / --yes)
if [ "$1" != "-y" ] && [ "$1" != "--yes" ]; then
    echo -n "Type 'yes' to confirm: "
    read CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled."
        exit 0
    fi
    echo ""
fi

STEP=1
TOTAL_STEPS=3

# Step 1: Stop Tekton port-forward and delete all K8s namespaces
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Resetting Tekton (stopping port-forward + deleting namespaces)..."

# Kill dashboard port-forward
DASHBOARD_PID_FILE="$LOG_DIR/tekton-dashboard.pid"
if [ -f "$DASHBOARD_PID_FILE" ]; then
    PID=$(cat "$DASHBOARD_PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        echo -e "${GREEN}✓${NC}  Dashboard port-forward stopped"
    fi
    rm -f "$DASHBOARD_PID_FILE"
fi

# Delete pipeline namespace (Tasks, Pipelines, PipelineRuns, EventListeners)
if kubectl get namespace "${PIPELINE_NAMESPACE}" &>/dev/null; then
    echo -e "${YELLOW}→${NC}  Deleting namespace '${PIPELINE_NAMESPACE}'..."
    kubectl delete namespace "${PIPELINE_NAMESPACE}" --wait=false 2>/dev/null || true
fi

# Delete shared Tekton namespace (controllers, dashboard, triggers)
if [ "${PIPELINE_NAMESPACE}" != "${TEKTON_NAMESPACE}" ]; then
    if kubectl get namespace "${TEKTON_NAMESPACE}" &>/dev/null; then
        echo -e "${YELLOW}→${NC}  Deleting namespace '${TEKTON_NAMESPACE}'..."
        kubectl delete namespace "${TEKTON_NAMESPACE}" --wait=false 2>/dev/null || true
    fi
fi

# Wait for namespaces to terminate using kubectl wait (event-driven, no sleep loops)
for ns in "${PIPELINE_NAMESPACE}" "${TEKTON_NAMESPACE}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo -e "   ${YELLOW}⏳${NC} Waiting for namespace '$ns' to terminate..."
        kubectl wait namespace/"$ns" --for=delete --timeout=180s 2>/dev/null && \
            echo -e "${GREEN}✓${NC}  Namespace '$ns' deleted" || \
            echo -e "${YELLOW}→${NC}  Namespace '$ns' still terminating (continuing)"
    fi
done

echo -e "${GREEN}✓${NC} Tekton reset"
STEP=$((STEP + 1))
echo ""

# Step 2: Remove Docker containers and volumes
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Removing Docker containers and volumes..."
cd "$ROOT_DIR/orchestration"
if [ "$PRESERVE_POSTGRES" = true ]; then
    echo -e "${GREEN}→${NC} Preserving postgres-data volume (default)"
    # Create a backup of postgres-data before removal
    BACKUP_DIR="$ROOT_DIR/backups/postgres"
    mkdir -p "$BACKUP_DIR"
    if docker run --rm -v postgres-data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/postgres-data-backup.tar.gz -C /data . 2>/dev/null; then
        echo -e "${GREEN}✓${NC} PostgreSQL data backed up to $BACKUP_DIR/postgres-data-backup.tar.gz"
    fi
    # Remove containers but keep postgres-data volume
    docker-compose down --remove-orphans 2>&1
    echo -e "${GREEN}✓${NC} Docker containers removed (postgres-data volume preserved)"
else
    echo -e "${YELLOW}→${NC} Wiping all volumes including postgres-data"
    if docker-compose down -v --remove-orphans 2>&1; then
        echo -e "${GREEN}✓${NC} Docker containers and volumes removed"
    else
        echo -e "${YELLOW}→${NC} Some resources may already be removed"
    fi
fi
STEP=$((STEP + 1))
echo ""

# Step 3: Delete k3d cluster (includes built-in registry)
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Deleting k3d cluster and registry..."
if command -v k3d &>/dev/null && k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    k3d cluster delete "${CLUSTER_NAME}"
    echo -e "${GREEN}✓${NC} k3d cluster deleted"
else
    echo -e "${YELLOW}→${NC} No k3d cluster found"
fi
echo ""

echo "================================="
echo -e "${GREEN}✅ Reset complete — everything deleted.${NC}"
echo "================================="
echo ""
echo "Ready for a fresh start: ./commands/start-all.sh"
echo ""
