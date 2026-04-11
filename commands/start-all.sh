#!/bin/bash
# Start all infrastructure services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Help function
show_help() {
    echo "Start All Infrastructure Services"
    echo ""
    echo "Usage: ./commands/start-all.sh [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "This script starts:"
    echo "  - Core infrastructure (Vault, Registry, Gravitee) via init.sh"
    echo "  - Tekton infrastructure (Pipelines, Dashboard)"
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
NC='\033[0m'

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

echo "🚀 Starting all infrastructure services..."
echo ""

STEP=1
TOTAL_STEPS=6

# Step 1: Start Docker services
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Starting Docker services (Vault, Gravitee)..."
cd "$ROOT_DIR/orchestration"

SERVICES=(vault gravitee-mongo gravitee-es gravitee-gateway gravitee-mgmt-api gravitee-mgmt-ui gravitee-portal-ui)

# Pre-check: clean up stopped containers that have conflicting names
for svc in "${SERVICES[@]}"; do
    STATE=$(docker inspect "$svc" --format='{{.State.Running}}' 2>/dev/null || echo "")
    if [ "$STATE" = "false" ]; then
        echo -e "   ${YELLOW}→${NC} Removing stopped container: $svc"
        docker rm "$svc" >/dev/null 2>&1 || true
    elif [ "$STATE" = "true" ]; then
        echo -e "   ${GREEN}✓${NC} Already running: $svc"
    fi
done
echo ""

# Now start services (stopped ones are removed, running ones will be skipped by docker-compose)
if docker-compose up -d "${SERVICES[@]}" 2>&1 | grep -v "is already running"; then
    echo -e "${GREEN}✓${NC} Docker services started/verified"
else
    echo -e "${YELLOW}→${NC} Docker services status checked"
fi
echo ""

STEP=2
# Step 2: Initialize / unseal Vault (idempotent — skips if already unsealed)
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Initializing / unsealing Vault..."
"$ROOT_DIR/services/vault/scripts/init-vault.sh"
echo ""

STEP=3
# Step 3: Create k3d cluster with built-in registry
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Creating k3d cluster with built-in registry..."
CLUSTER_NAME="${CLUSTER_NAME:-dev-infra}"
if k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
    echo -e "${YELLOW}→${NC} k3d cluster already exists"
else
    k3d cluster create "${CLUSTER_NAME}" \
        --registry-create k3d-${CLUSTER_NAME}-registry:${REGISTRY_PORT:-5002} \
        --agents 0 \
        --k3s-arg "--disable=traefik@server:0"
    echo -e "${GREEN}✓${NC} k3d cluster created with built-in registry"
fi
echo ""

STEP=4
# Step 4: Verify k3d registry
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Verifying k3d built-in registry..."
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${REGISTRY_PORT:-5002}/v2/" | grep -q "200"; then
    echo -e "${GREEN}✓${NC} Registry accessible at localhost:${REGISTRY_PORT:-5002}"
else
    echo -e "${YELLOW}→${NC} Registry not yet reachable — may take a few seconds"
fi
echo ""

STEP=5
# Step 5: Set kubectl context and apply K8s prerequisites
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Setting kubectl context and applying K8s prerequisites..."
K3D_CONFIG=$(k3d kubeconfig write "${CLUSTER_NAME}" --output /tmp/k3d-config-${CLUSTER_NAME} 2>/dev/null && echo /tmp/k3d-config-${CLUSTER_NAME})
if [ -f "$HOME/.kube/config" ]; then
    KUBECONFIG=/tmp/k3d-config-${CLUSTER_NAME}:$HOME/.kube/config kubectl config view --flatten > /tmp/merged-config
    mv /tmp/merged-config "$HOME/.kube/config"
else
    mkdir -p "$HOME/.kube"
    cp /tmp/k3d-config-${CLUSTER_NAME} "$HOME/.kube/config"
fi
kubectl config use-context k3d-${CLUSTER_NAME}
rm -f /tmp/k3d-config-${CLUSTER_NAME}

# Apply K8s prerequisites with env substitution for RBAC
envsubst '${RBAC_USER} ${NAMESPACE}' < "$ROOT_DIR/services/k8s-setup/rbac-rolebinding.yaml" | kubectl apply -f -
kubectl apply -f "$ROOT_DIR/services/k8s-setup/" --recursive
echo -e "${GREEN}✓${NC} K8s prerequisites applied"
echo ""

STEP=6
# Step 6: Install Tekton infrastructure
echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} Installing Tekton infrastructure (mode controlled by .env)..."
"$ROOT_DIR/services/tekton/scripts/start.sh"
echo ""

echo "================================="
echo -e "${GREEN}✅ All services started!${NC}"
echo "================================="
echo ""
echo "📋 Access Services:"
echo "   Vault:      http://localhost:${VAULT_PORT:-8201}"
echo "   Gravitee:   http://localhost:${GRAVITEE_MGMT_UI_PORT:-8084}"
echo "   Dashboard:  http://localhost:${TEKTON_DASHBOARD_PORT:-9097}"
echo ""
echo "🔗 Dashboard port-forward (auto-started above):"
echo "   kubectl port-forward -n ${TEKTON_NAMESPACE:-tekton-pipelines} --disable-compression \\"
echo "     svc/tekton-dashboard ${TEKTON_DASHBOARD_PORT:-9097}:${TEKTON_DASHBOARD_PORT:-9097}"
echo ""
echo "🔧 Check status:"
echo "   ./commands/status-all.sh"
echo ""
