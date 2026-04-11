#!/bin/bash
# Check status of all infrastructure services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

# Use environment variables with defaults
VAULT_PORT="${VAULT_PORT:-8201}"
REGISTRY_PORT="${REGISTRY_PORT:-5002}"
GRAVITEE_MONGO_PORT="${GRAVITEE_MONGO_PORT:-27017}"
GRAVITEE_ES_PORT="${GRAVITEE_ES_PORT:-9200}"
GRAVITEE_GATEWAY_PORT="${GRAVITEE_GATEWAY_PORT:-8082}"
GRAVITEE_MGMT_API_PORT="${GRAVITEE_MGMT_API_PORT:-8083}"
GRAVITEE_MGMT_UI_PORT="${GRAVITEE_MGMT_UI_PORT:-8084}"
GRAVITEE_PORTAL_UI_PORT="${GRAVITEE_PORTAL_UI_PORT:-8085}"
TEKTON_DASHBOARD_PORT="${TEKTON_DASHBOARD_PORT:-9097}"
CLUSTER_NAME="${CLUSTER_NAME:-dev-infra}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "📊 Dev Infrastructure Status"
echo "============================"
echo ""

# Define services
SERVICES=(
    "vault:Vault:$VAULT_PORT"
    "gravitee-mongo:Gravitee MongoDB:$GRAVITEE_MONGO_PORT"
    "gravitee-es:Gravitee Elasticsearch:$GRAVITEE_ES_PORT"
    "gravitee-gateway:Gravitee Gateway:$GRAVITEE_GATEWAY_PORT"
    "gravitee-mgmt-api:Gravitee Management API:$GRAVITEE_MGMT_API_PORT"
    "gravitee-mgmt-ui:Gravitee Management UI:$GRAVITEE_MGMT_UI_PORT"
    "gravitee-portal-ui:Gravitee Portal UI:$GRAVITEE_PORTAL_UI_PORT"
)

TEKTON_DASHBOARD_PORT=$(grep TEKTON_DASHBOARD_PORT "$ROOT_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "9097")
TEKTON_DASHBOARD_PORT=${TEKTON_DASHBOARD_PORT:-9097}
CLUSTER_NAME=$(grep '^CLUSTER_NAME' "$ROOT_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "dev-infra")
CLUSTER_NAME=${CLUSTER_NAME:-dev-infra}

printf "%-25s %-15s %-10s %s\n" "SERVICE" "CONTAINER" "PORT" "HEALTH"
printf "%-25s %-15s %-10s %s\n" "-------" "---------" "----" "------"

for svc in "${SERVICES[@]}"; do
    IFS=':' read -r container name port <<< "$svc"
    
    # Check if container is running
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        status="${GREEN}✅ running${NC}"

        # Skip port check for services with no exposed port
        if [ "$port" = "-" ]; then
            health="${GREEN}✅ running${NC}"
        elif curl -s "http://localhost:$port" > /dev/null 2>&1 || \
           curl -s "http://localhost:$port/_cluster/health" > /dev/null 2>&1 || \
           nc -z localhost "$port" 2>/dev/null; then
            health="${GREEN}✅ reachable${NC}"
        else
            health="${YELLOW}⏳ starting${NC}"
        fi
    else
        status="${RED}❌ stopped${NC}"
        health="${RED}❌ down${NC}"
    fi
    
    printf "%-25s %-15s %-10s %b\n" "$name" "$container" "$port" "$health"
done

echo ""
echo "🔍 Quick Health Checks:"
echo ""

# Vault status
if curl -s http://localhost:$VAULT_PORT/v1/sys/health > /dev/null 2>&1; then
    vault_status=$(curl -s http://localhost:$VAULT_PORT/v1/sys/health | grep -o '"sealed":false' > /dev/null && echo "unsealed" || echo "sealed")
    echo -e "   Vault: ${GREEN}$vault_status${NC} (port $VAULT_PORT)"
else
    echo -e "   Vault: ${RED}unavailable${NC} (port $VAULT_PORT)"
fi

# Registry status (k3d managed)
if curl -s http://localhost:$REGISTRY_PORT/v2/_catalog > /dev/null 2>&1; then
    echo -e "   Registry: ${GREEN}API reachable (port $REGISTRY_PORT, k3d managed)${NC}"
else
    echo -e "   Registry: ${RED}unavailable${NC} (start k3d cluster first)"
fi

# Gravitee gateway
if curl -s "http://localhost:${GRAVITEE_GATEWAY_PORT:-8082}" > /dev/null 2>&1; then
    echo -e "   Gravitee GW: ${GREEN}reachable${NC}"
else
    echo -e "   Gravitee GW: ${RED}unavailable${NC}"
fi

# k3d cluster
if command -v k3d &>/dev/null && k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo -e "   k3d Cluster: ${GREEN}running${NC} (${CLUSTER_NAME})"
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${TEKTON_DASHBOARD_PORT}" 2>/dev/null | grep -qE "200|302"; then
        echo -e "   Tekton:      ${GREEN}dashboard reachable on port ${TEKTON_DASHBOARD_PORT}${NC}"
    else
        echo -e "   Tekton:      ${YELLOW}cluster up, dashboard not forwarded${NC} (start with: ./scripts/start-service.sh tekton)"
    fi
else
    echo -e "   k3d Cluster: ${RED}not running${NC}"
    echo -e "   Tekton:      ${RED}unavailable${NC} (start with: ./scripts/start-service.sh tekton)"
fi

echo ""
