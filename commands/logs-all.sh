#!/bin/bash
# Get logs from all infrastructure services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Help function
show_help() {
    echo "Get Logs from Infrastructure Services"
    echo ""
    echo "Usage: ./commands/logs-all.sh [options] <service> [run-name]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Services:"
    echo "  vault              - HashiCorp Vault logs"
    echo "  registry           - Docker Registry logs (k3d managed)"
    echo "  gravitee           - API Gateway logs"
    echo "  tekton             - Most recent PipelineRun step logs (live)"
    echo "  tekton <run-name>  - Specific PipelineRun step logs (live)"
    echo "  tekton-runs        - List recent PipelineRuns with status"
    echo "  tekton-dashboard   - Tekton Dashboard pod logs (infrastructure)"
    echo ""
    echo "Examples:"
    echo "  ./commands/logs-all.sh tekton"
    echo "  ./commands/logs-all.sh tekton my-pipeline-run-abc12"
    echo "  ./commands/logs-all.sh tekton-runs"
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

# Check if service name is provided
if [ -z "$1" ]; then
    echo "📋 Available services:"
    echo "   vault"
    echo "   registry (k3d managed)"
    echo "   gravitee"
    echo "   tekton [run-name]   pipeline step logs (most recent run if no name given)"
    echo "   tekton-runs         list recent PipelineRuns with status"
    echo "   tekton-dashboard    Tekton Dashboard pod logs (infrastructure)"
    echo ""
    echo "Usage: ./logs-all.sh <service> [run-name]"
    echo ""
    exit 1
fi

SERVICE="$1"
NS="${PIPELINE_NAMESPACE:-tekton-pipelines}"
TEKTON_NS="${TEKTON_NAMESPACE:-tekton-pipelines}"

echo "📜 Fetching logs for: $SERVICE"
echo "================================"
echo ""

case "$SERVICE" in
    vault)
        cd "$ROOT_DIR/orchestration"
        docker-compose logs -f vault
        ;;
    registry)
        docker logs -f k3d-${CLUSTER_NAME:-dev-infra}-registry 2>&1
        ;;
    gravitee)
        cd "$ROOT_DIR/orchestration"
        docker-compose logs -f gravitee-*
        ;;
    tekton)
        RUN_NAME="${2:-}"
        if [ -z "$RUN_NAME" ]; then
            # Find the most recent PipelineRun
            RUN_NAME=$(kubectl get pipelineruns -n "$NS" \
                --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null \
                | tail -1 | awk '{print $1}')
            if [ -z "$RUN_NAME" ]; then
                echo -e "${YELLOW}No PipelineRuns found in namespace: $NS${NC}"
                echo "Tip: trigger a run first, then check logs here."
                exit 1
            fi
            echo -e "${BLUE}ℹ${NC}  Streaming most recent run: ${GREEN}${RUN_NAME}${NC}"
            echo "   (pass a run name to target a specific one)"
            echo ""
        else
            echo -e "${BLUE}ℹ${NC}  Streaming run: ${GREEN}${RUN_NAME}${NC}"
            echo ""
        fi
        # Stream logs from all step containers in the PipelineRun pods
        kubectl logs -n "$NS" \
            -l "tekton.dev/pipelineRun=${RUN_NAME}" \
            --all-containers \
            --prefix \
            --follow \
            --tail=200 2>/dev/null || \
        # Fallback: try as a TaskRun name
        kubectl logs -n "$NS" \
            -l "tekton.dev/taskRun=${RUN_NAME}" \
            --all-containers \
            --prefix \
            --follow \
            --tail=200
        ;;
    tekton-runs)
        echo "Recent PipelineRuns (namespace: $NS):"
        echo ""
        kubectl get pipelineruns -n "$NS" \
            --sort-by=.metadata.creationTimestamp \
            -o custom-columns=\
"NAME:.metadata.name,\
PIPELINE:.spec.pipelineRef.name,\
STATUS:.status.conditions[-1].reason,\
STARTED:.metadata.creationTimestamp" \
            --no-headers 2>/dev/null | tail -10 \
            | while IFS= read -r line; do printf "   %s\n" "$line"; done
        echo ""
        echo "Stream logs: ./commands/logs-all.sh tekton <run-name>"
        ;;
    tekton-dashboard)
        echo "Tekton Dashboard pod logs (namespace: $TEKTON_NS):"
        kubectl logs -n "$TEKTON_NS" -l app=tekton-dashboard --tail=100 -f
        ;;
    *)
        echo -e "${YELLOW}⚠️  Unknown service: $SERVICE${NC}"
        echo "Available: vault, registry, gravitee, tekton, tekton-runs, tekton-dashboard"
        exit 1
        ;;
esac
