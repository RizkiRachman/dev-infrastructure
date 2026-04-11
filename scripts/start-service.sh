#!/bin/bash
# Start a specific service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

VAULT_PORT=${VAULT_PORT:-8201}
REGISTRY_PORT=${REGISTRY_PORT:-5002}
GRAVITEE_MGMT_UI_PORT=${GRAVITEE_MGMT_UI_PORT:-8084}
TEKTON_DASHBOARD_PORT=${TEKTON_DASHBOARD_PORT:-9097}

if [ -z "$1" ]; then
    echo "Usage: ./start-service.sh <service>"
    echo ""
    echo "Available services:"
    echo -e "  ${BLUE}vault${NC}       - HashiCorp Vault secrets manager     → http://localhost:$VAULT_PORT"
    echo -e "  ${BLUE}registry${NC}    - Docker image registry (k3d managed) → http://localhost:$REGISTRY_PORT"
    echo -e "  ${BLUE}gravitee${NC}    - API Gateway (gateway + UI + portal)  → http://localhost:$GRAVITEE_MGMT_UI_PORT"
    echo -e "  ${BLUE}tekton${NC}      - Tekton CI/CD (K8s + Tekton)         → http://localhost:$TEKTON_DASHBOARD_PORT"
    echo ""
    exit 1
fi

SERVICE="$1"
cd "$ROOT_DIR/orchestration"

case "$SERVICE" in
    vault)
        echo -e "${BLUE}🔐 Starting Vault...${NC}"
        # Check if container exists but is stopped
        if STATE=$(docker inspect vault --format='{{.State.Running}}' 2>/dev/null); then
            if [ "$STATE" = "true" ]; then
                echo -e "${GREEN}✓${NC} Vault already running"
            else
                echo -e "${YELLOW}→${NC} Removing stopped vault container..."
                docker rm vault >/dev/null 2>&1
                docker-compose up -d vault
            fi
        else
            docker-compose up -d vault
        fi
        sleep 5
        "$ROOT_DIR/services/vault/scripts/init-vault.sh"
        echo ""
        echo -e "${GREEN}✅ Vault ready${NC}"
        echo "   UI:    http://localhost:$VAULT_PORT"
        echo "   Token: ${VAULT_TOKEN:-dev-root-token}"
        ;;
    registry)
        echo -e "${BLUE}📦 Registry is managed by k3d...${NC}"
        if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME:-dev-infra}"; then
            echo -e "${GREEN}✅ Registry ready (k3d managed)${NC}"
            echo "   API: http://localhost:$REGISTRY_PORT"
        else
            echo -e "${YELLOW}⚠️  k3d cluster not running. Start it first:${NC}"
            echo "   ./scripts/init.sh  (option 1)"
        fi
        ;;
    gravitee)
        echo -e "${BLUE}🌐 Starting Gravitee API Gateway...${NC}"

        GRAVITEE_CONTAINERS=(gravitee-mongo gravitee-es gravitee-gateway gravitee-mgmt-api gravitee-mgmt-ui gravitee-portal-ui)

        # Pre-check and clean up stopped containers
        for container in "${GRAVITEE_CONTAINERS[@]}"; do
            if STATE=$(docker inspect "$container" --format='{{.State.Running}}' 2>/dev/null); then
                if [ "$STATE" = "false" ]; then
                    echo -e "   ${YELLOW}→${NC} Removing stopped container: $container"
                    docker rm "$container" >/dev/null 2>&1 || true
                fi
            fi
        done

        echo -e "   ${YELLOW}⏳ Starting dependencies (MongoDB + Elasticsearch)...${NC}"
        docker-compose up -d gravitee-mongo gravitee-es
        sleep 15
        echo -e "   ${YELLOW}⏳ Starting gateway services...${NC}"
        docker-compose up -d gravitee-gateway gravitee-mgmt-api gravitee-mgmt-ui gravitee-portal-ui
        echo ""
        echo -e "${GREEN}✅ Gravitee ready${NC}"
        echo "   Management UI: http://localhost:$GRAVITEE_MGMT_UI_PORT  (admin / admin)"
        echo "   Gateway:       http://localhost:${GRAVITEE_GATEWAY_PORT:-8082}"
        echo "   Portal:        http://localhost:${GRAVITEE_PORTAL_UI_PORT:-8085}"
        ;;
    tekton)
        "$ROOT_DIR/services/tekton/scripts/start.sh"
        ;;
    *)
        echo "Unknown service: $SERVICE"
        echo "Run without arguments to see available services"
        exit 1
        ;;
esac
