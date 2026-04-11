#!/bin/bash
# Register a service's Tekton pipeline to the shared dev-infrastructure
# Usage: ./register-service.sh <service-name> <path-to-service-tekton-dir>
#
# Example:
#   ./register-service.sh goods-price ../goods-price-comparison-service/ci/local/tekton

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$(dirname "$SERVICE_DIR")")"

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
SERVICE_NAME="${1:-}"
TEKTON_DIR="${2:-}"

show_help() {
    cat << EOF
Register a service's Tekton pipeline to the shared dev-infrastructure

Usage:
  $0 <service-name> <path-to-tekton-directory>

Arguments:
  service-name          Name of the service (e.g., goods-price, api-gateway)
  path-to-tekton-dir    Path to the service's Tekton manifests directory
                        (should contain tasks/, pipeline.yaml, etc.)

Examples:
  # Register goods-price service
  $0 goods-price ../goods-price-comparison-service/ci/local/tekton

  # Register from within service repo
  cd goods-price-comparison-service
  $0 goods-price ./ci/local/tekton

Directory Structure Expected:
  <tekton-dir>/
  ├── 01-tasks/          # Service-specific tasks (maven-build, go-build, etc.)
  ├── pipeline.yaml      # Pipeline definition
  └── pipeline-run.yaml  # Example PipelineRun (optional)

Prerequisites:
  - Dev infrastructure must be running (./start.sh)
  - kubectl configured to use a Kubernetes context (k3d, Docker Desktop, Rancher Desktop, etc.)
EOF
}

if [ -z "$SERVICE_NAME" ] || [ "$SERVICE_NAME" = "--help" ] || [ "$SERVICE_NAME" = "-h" ]; then
    show_help
    exit 0
fi

if [ -z "$TEKTON_DIR" ]; then
    echo -e "${RED}Error: Path to Tekton directory is required${NC}"
    show_help
    exit 1
fi

# Resolve path
if [[ "$TEKTON_DIR" != /* ]]; then
    TEKTON_DIR="$(pwd)/$TEKTON_DIR"
fi

if [ ! -d "$TEKTON_DIR" ]; then
    echo -e "${RED}Error: Directory not found: $TEKTON_DIR${NC}"
    exit 1
fi

echo "🔧 Registering service: ${BLUE}${SERVICE_NAME}${NC}"
echo "   Tekton directory: ${TEKTON_DIR}"
echo "   Namespace: ${PIPELINE_NAMESPACE}"
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."
if ! kubectl get namespace "${PIPELINE_NAMESPACE}" &>/dev/null; then
    echo -e "${RED}Error: Namespace '${PIPELINE_NAMESPACE}' not found${NC}"
    echo "   Run dev-infrastructure setup first: ./services/tekton/scripts/start.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} Namespace exists"

# Apply tasks
echo ""
echo "📦 Applying service-specific tasks..."
if [ -d "$TEKTON_DIR/01-tasks" ] && ls "$TEKTON_DIR/01-tasks"/*.yaml &>/dev/null; then
    # Apply the entire directory in a single kubectl call instead of one-per-file
    kubectl apply -f "$TEKTON_DIR/01-tasks/" -n "${PIPELINE_NAMESPACE}" >/dev/null 2>&1 && \
        echo -e "${GREEN}✓${NC}  All tasks applied" || \
        echo -e "${YELLOW}→${NC}  Tasks (may already exist)"
    # Show which tasks were registered
    for task in "$TEKTON_DIR/01-tasks"/*.yaml; do
        [ -f "$task" ] && echo "   → $(basename "$task" .yaml)"
    done
else
    echo -e "${YELLOW}→${NC} No tasks directory found (optional)"
fi

# Apply pipeline
echo ""
echo "📋 Applying pipeline..."
if [ -f "$TEKTON_DIR/pipeline.yaml" ]; then
    kubectl apply -f "$TEKTON_DIR/pipeline.yaml" -n "${PIPELINE_NAMESPACE}" > /dev/null 2>&1 && \
        echo -e "${GREEN}✓${NC} Pipeline applied" || \
        echo -e "${YELLOW}→${NC} Pipeline may already exist"
else
    echo -e "${YELLOW}⚠${NC} pipeline.yaml not found"
fi

# List available PipelineRuns
echo ""
echo "🚀 Available PipelineRuns:"
if [ -f "$TEKTON_DIR/pipeline-run.yaml" ]; then
    echo -e "   ${GREEN}✓${NC} $TEKTON_DIR/pipeline-run.yaml"
fi
if [ -f "$TEKTON_DIR/pipeline-run-quay.yaml" ]; then
    echo -e "   ${GREEN}✓${NC} $TEKTON_DIR/pipeline-run-quay.yaml"
fi

echo ""
echo -e "${GREEN}✓${NC} Service '${SERVICE_NAME}' registered successfully!"
echo ""
echo "Next steps:"
echo "   Run pipeline: kubectl create -f $TEKTON_DIR/pipeline-run.yaml -n ${PIPELINE_NAMESPACE}"
echo "   Check status: kubectl get pipelineruns -n ${PIPELINE_NAMESPACE}"
echo "   View logs:    ./commands/logs-all.sh tekton <run-name>"
echo "   List runs:    ./commands/logs-all.sh tekton-runs"
echo ""
