#!/bin/bash
# Check status of Tekton components

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

CLUSTER_NAME="${CLUSTER_NAME:-dev-infra}"
TEKTON_NS="${TEKTON_NAMESPACE:-tekton-pipelines}"
PIPELINE_NS="${PIPELINE_NAMESPACE:-tekton-pipelines}"
TEKTON_DASHBOARD_PORT="${TEKTON_DASHBOARD_PORT:-9097}"
TEKTON_PROXY_PORT="${TEKTON_PROXY_PORT:-8001}"
TEKTON_LIGHTWEIGHT="${TEKTON_LIGHTWEIGHT:-false}"
TEKTON_INSTALL_DASHBOARD="${TEKTON_INSTALL_DASHBOARD:-true}"
TEKTON_INSTALL_TRIGGERS="${TEKTON_INSTALL_TRIGGERS:-true}"
if [ "$TEKTON_LIGHTWEIGHT" = true ]; then
    TEKTON_INSTALL_DASHBOARD=false
    TEKTON_INSTALL_TRIGGERS=false
fi
LOG_DIR="$ROOT_DIR/logs"

echo "📊 Tekton Status"
echo "================"
echo ""
echo -e "${BLUE}ℹ${NC}  Tekton Infrastructure (namespace: ${TEKTON_NS})"
echo -e "${BLUE}ℹ${NC}  Pipeline Resources (namespace: ${PIPELINE_NS})"
if [ "$TEKTON_LIGHTWEIGHT" = true ]; then
echo -e "${BLUE}ℹ${NC}  Mode: lightweight (Pipelines only)"
fi
echo ""

# ── k8s cluster ──────────────────────────────────────────────────────────────
echo "☸  Kubernetes cluster:"
if kubectl cluster-info &>/dev/null; then
    K8S_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
    echo -e "   ${GREEN}✅ connected${NC} (context: ${K8S_CONTEXT})"
    CLUSTER_UP=true
else
    echo -e "   ${RED}❌ not connected${NC}"
    CLUSTER_UP=false
fi
echo ""

if [ "$CLUSTER_UP" = false ]; then
    echo "   Ensure kubectl is connected to a cluster:"
    echo "   - k3d: ./scripts/init.sh (option 1)"
    echo "   - Existing cluster: kubectl config use-context <context>"
    exit 0
fi

# ── Tekton core deployments ──────────────────────────────────────────────────
echo "📦 Tekton Infrastructure (namespace: ${TEKTON_NS}):"
printf "   %-40s %s\n" "DEPLOYMENT" "STATUS"
printf "   %-40s %s\n" "----------" "------"

DEPLOYMENTS=(
    "tekton-pipelines-controller"
    "tekton-pipelines-webhook"
)

if [ "$TEKTON_INSTALL_TRIGGERS" = true ]; then
    DEPLOYMENTS+=(
        "tekton-triggers-controller"
        "tekton-triggers-webhook"
    )
fi

if [ "$TEKTON_INSTALL_DASHBOARD" = true ]; then
    DEPLOYMENTS+=("tekton-dashboard")
fi

for deploy in "${DEPLOYMENTS[@]}"; do
    read -r READY DESIRED < <(kubectl get deployment "$deploy" -n "${TEKTON_NS}" \
        --no-headers -o custom-columns=READY:.status.readyReplicas,DESIRED:.spec.replicas 2>/dev/null \
        || echo "N/A N/A")
    if [ "$READY" = "$DESIRED" ] && [ "$READY" != "N/A" ] && [ "$READY" != "" ]; then
        printf "   ${GREEN}✅${NC} %-38s %s/%s\n" "$deploy" "$READY" "$DESIRED"
    elif [ "$READY" = "N/A" ]; then
        printf "   ${RED}❌${NC} %-38s not installed\n" "$deploy"
    else
        printf "   ${YELLOW}⏳${NC} %-38s %s/%s\n" "$deploy" "${READY:-0}" "${DESIRED:-0}"
    fi
done
echo ""

# ── Pipeline namespace resources ──────────────────────────────────────────────
echo "🛠  Pipeline Resources (namespace: ${PIPELINE_NS}):"

if ! kubectl get namespace "${PIPELINE_NS}" &>/dev/null; then
    echo -e "   ${RED}❌ namespace not found${NC} — run start.sh to apply manifests"
else
    TASK_COUNT=$(kubectl get tasks -n "${PIPELINE_NS}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    PIPELINE_COUNT=$(kubectl get pipelines -n "${PIPELINE_NS}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    TRIGGER_COUNT=$(kubectl get eventlisteners -n "${PIPELINE_NS}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    PIPELINERUN_COUNT=$(kubectl get pipelineruns -n "${PIPELINE_NS}" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    echo -e "   ${GREEN}✓${NC}  Tasks:         ${TASK_COUNT}"
    echo -e "   ${GREEN}✓${NC}  Pipelines:     ${PIPELINE_COUNT}"
    echo -e "   ${GREEN}✓${NC}  EventListeners:${TRIGGER_COUNT}"
    echo -e "   ${BLUE}ℹ${NC}  PipelineRuns:  ${PIPELINERUN_COUNT}"
fi
echo ""

# ── Recent PipelineRuns ───────────────────────────────────────────────────────
echo "🏃 Recent PipelineRuns (${PIPELINE_NS}):"
RUNS=$(kubectl get pipelineruns -n "${PIPELINE_NS}" \
    --sort-by=.metadata.creationTimestamp \
    -o custom-columns=NAME:.metadata.name,PIPELINE:.spec.pipelineRef.name,STATUS:.status.conditions[-1].reason,START:.metadata.creationTimestamp \
    --no-headers 2>/dev/null | tail -5)

if [ -z "$RUNS" ]; then
    echo "   No pipeline runs found."
else
    printf "   %-40s %-20s %-15s %s\n" "NAME" "PIPELINE" "STATUS" "STARTED"
    printf "   %-40s %-20s %-15s %s\n" "----" "--------" "------" "-------"
    while IFS= read -r line; do
        printf "   %s\n" "$line"
    done <<< "$RUNS"
fi
echo ""

# ── Dashboard ────────────────────────────────────────────────────────────────
if [ "$TEKTON_INSTALL_DASHBOARD" = true ]; then
    echo "🖥  Dashboard (kubectl proxy):"
    PROXY_PID_FILE="$LOG_DIR/kubectl-proxy.pid"

    DASHBOARD_POD=$(kubectl get pod -n "${TEKTON_NS}" \
        -l app=tekton-dashboard --no-headers 2>/dev/null | awk 'NR==1{print $1}')

    PROXY_PID=""
    [ -f "$PROXY_PID_FILE" ] && PROXY_PID=$(cat "$PROXY_PID_FILE")

    PROXY_ALIVE=false
    [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null && PROXY_ALIVE=true

    PROXY_REACHABLE=false
    curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:${TEKTON_PROXY_PORT}" 2>/dev/null \
        | grep -qE "200|400" && PROXY_REACHABLE=true

    DASHBOARD_URL="http://localhost:${TEKTON_PROXY_PORT}/api/v1/namespaces/${PIPELINE_NS}/services/tekton-dashboard:${TEKTON_DASHBOARD_PORT}/proxy/"

    if [ "$PROXY_ALIVE" = true ] && [ "$PROXY_REACHABLE" = true ]; then
        echo -e "   ${GREEN}✅ reachable${NC}  ${DASHBOARD_URL}"
        echo -e "   ${BLUE}ℹ${NC}  kubectl proxy PID: $PROXY_PID"
        [ -n "$DASHBOARD_POD" ] && echo -e "   ${BLUE}ℹ${NC}  Dashboard pod: ${DASHBOARD_POD}"
    elif [ "$PROXY_ALIVE" = true ]; then
        echo -e "   ${YELLOW}⏳ proxy running, waiting for ready${NC}  (PID: $PROXY_PID)"
        [ -n "$DASHBOARD_POD" ] && echo -e "   ${BLUE}ℹ${NC}  Dashboard pod: ${DASHBOARD_POD}"
        echo -e "   ${BLUE}ℹ${NC}  Logs:    $LOG_DIR/kubectl-proxy.log"
    else
        echo -e "   ${RED}❌ kubectl proxy not running${NC}"
        if [ -n "$DASHBOARD_POD" ]; then
            echo -e "   ${BLUE}ℹ${NC}  Dashboard pod is ${GREEN}up${NC}: ${DASHBOARD_POD}"
            echo -e "   ${BLUE}ℹ${NC}  Start proxy:"
            echo "        $SCRIPT_DIR/start.sh"
            echo -e "   ${BLUE}ℹ${NC}  Or manually:"
            echo "        kubectl proxy --port=${TEKTON_PROXY_PORT}"
        else
            echo -e "   ${YELLOW}⚠${NC}  Dashboard pod not found — run start.sh first"
            echo "        $SCRIPT_DIR/start.sh"
        fi
    fi
else
    echo "🖥  Dashboard: skipped (TEKTON_INSTALL_DASHBOARD=false)"
fi
echo ""
