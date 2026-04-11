#!/bin/bash
# Start Tekton Infrastructure
# Sets up generic Kubernetes resources for Tekton pipelines
# Services manage their own Tekton installation (pipelines, tasks, triggers)
#
# Modes:
#   TEKTON_LIGHTWEIGHT=true  → Pipelines only (2 pods, no Dashboard/Triggers)
#   TEKTON_LIGHTWEIGHT=false → Pipelines + optional Dashboard + optional Triggers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$(dirname "$SERVICE_DIR")")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

# ── Configuration (all from env, no hardcoded values) ─────────────────────────
TEKTON_NS="${TEKTON_NAMESPACE:-tekton-pipelines}"
PIPELINE_NS="${PIPELINE_NAMESPACE:-tekton-pipelines}"
PIPELINE_SA="${PIPELINE_SERVICE_ACCOUNT:-tekton-sa}"
TEKTON_LIGHTWEIGHT="${TEKTON_LIGHTWEIGHT:-false}"
TEKTON_INSTALL_DASHBOARD="${TEKTON_INSTALL_DASHBOARD:-true}"
TEKTON_INSTALL_TRIGGERS="${TEKTON_INSTALL_TRIGGERS:-true}"
TEKTON_READY_TIMEOUT="${TEKTON_READY_TIMEOUT:-180}"
TEKTON_DASHBOARD_PORT="${TEKTON_DASHBOARD_PORT:-9097}"
TEKTON_PROXY_PORT="${TEKTON_PROXY_PORT:-8001}"
TEKTON_PIPELINE_RELEASE_URL="${TEKTON_PIPELINE_RELEASE_URL:-https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml}"
TEKTON_DASHBOARD_RELEASE_URL="${TEKTON_DASHBOARD_RELEASE_URL:-https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml}"
TEKTON_TRIGGERS_RELEASE_URL="${TEKTON_TRIGGERS_RELEASE_URL:-https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml}"

# In lightweight mode, force-disable Dashboard and Triggers
if [ "$TEKTON_LIGHTWEIGHT" = true ]; then
    TEKTON_INSTALL_DASHBOARD=false
    TEKTON_INSTALL_TRIGGERS=false
fi

LOG_DIR="$ROOT_DIR/logs"
MANIFEST_DIR="$SERVICE_DIR/manifests"

echo "🚀 Starting Tekton Infrastructure..."
if [ "$TEKTON_LIGHTWEIGHT" = true ]; then
    echo "   Mode: lightweight (Pipelines only)"
else
    echo "   Mode: full (Dashboard=${TEKTON_INSTALL_DASHBOARD}, Triggers=${TEKTON_INSTALL_TRIGGERS})"
fi
echo ""

# ── Prerequisite checks ───────────────────────────────────────────────────────
echo "🔍 Checking prerequisites..."

check_tool() {
    local tool=$1 install_hint=$2
    if ! command -v "$tool" &>/dev/null; then
        echo -e "${RED}✗ '$tool' not found.${NC} $install_hint"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} $tool"
}

check_tool kubectl   "Install: brew install kubectl"
check_tool envsubst  "Install: brew install gettext"

# Check k8s connection
echo -n "   Checking k8s connection... "
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}✗${NC}"
    echo -e "${RED}ERROR: kubectl cannot connect to a Kubernetes cluster.${NC}"
    echo "   Options:"
    echo "   1. Start k3d cluster: ./scripts/init.sh (option 1)"
    echo "   2. Connect to an existing cluster: kubectl config use-context <context>"
    exit 1
fi
K8S_CONTEXT=$(kubectl config current-context)
echo -e "${GREEN}✓${NC} (context: ${K8S_CONTEXT})"

echo ""

# ── Apply manifests helper ────────────────────────────────────────────────────
apply_template() {
    local file="$1"
    local vars="$2"
    local label="$3"
    envsubst "$vars" < "$file" | kubectl apply -f - >/dev/null && \
        echo -e "${GREEN}✓${NC}  $label" || \
        echo -e "${YELLOW}→${NC}  $label (may already exist)"
}

# ── Install Tekton Pipelines ──────────────────────────────────────────────────
echo "📦 Installing Tekton Pipelines..."
if kubectl get namespace "$TEKTON_NS" &>/dev/null && \
   kubectl get deployment tekton-pipelines-controller -n "$TEKTON_NS" &>/dev/null; then
    echo -e "${CYAN}↺${NC}  Tekton Pipelines already installed"
else
    kubectl create namespace "$TEKTON_NS" 2>/dev/null || true

    kubectl apply -f "$TEKTON_PIPELINE_RELEASE_URL" >/dev/null
    echo -e "${GREEN}✓${NC}  Tekton Pipelines applied"
fi
echo ""

# ── Determine what needs installing / waiting ─────────────────────────────────
INSTALL_DASHBOARD=false
INSTALL_TRIGGERS=false

if [ "$TEKTON_INSTALL_DASHBOARD" = true ]; then
    if kubectl get deployment tekton-dashboard -n "$TEKTON_NS" &>/dev/null; then
        echo -e "${CYAN}↺${NC}  Tekton Dashboard already installed"
    else
        INSTALL_DASHBOARD=true
    fi
fi

if [ "$TEKTON_INSTALL_TRIGGERS" = true ]; then
    if kubectl get deployment tekton-triggers-controller -n "$TEKTON_NS" &>/dev/null; then
        echo -e "${CYAN}↺${NC}  Tekton Triggers already installed"
    else
        INSTALL_TRIGGERS=true
    fi
fi

# ── Apply Dashboard + Triggers manifests in parallel ─────────────────────────
if [ "$INSTALL_DASHBOARD" = true ] || [ "$INSTALL_TRIGGERS" = true ]; then
    echo "📦 Applying Dashboard + Triggers manifests in parallel..."

    if [ "$INSTALL_DASHBOARD" = true ]; then
        kubectl apply -f "$TEKTON_DASHBOARD_RELEASE_URL" >/dev/null &
        DB_APPLY_PID=$!
    fi

    if [ "$INSTALL_TRIGGERS" = true ]; then
        kubectl apply -f "$TEKTON_TRIGGERS_RELEASE_URL" >/dev/null 2>&1 &
        TR_APPLY_PID=$!
    fi

    if [ "$INSTALL_DASHBOARD" = true ]; then
        if wait $DB_APPLY_PID; then
            echo -e "${GREEN}✓${NC}  Tekton Dashboard applied"
        else
            echo -e "${YELLOW}→${NC}  Tekton Dashboard apply had issues, continuing..."
        fi
    fi

    if [ "$INSTALL_TRIGGERS" = true ]; then
        if wait $TR_APPLY_PID; then
            echo -e "${GREEN}✓${NC}  Tekton Triggers applied"
        else
            echo -e "${YELLOW}→${NC}  Retrying Triggers installation..."
            kubectl apply -f "$TEKTON_TRIGGERS_RELEASE_URL" >/dev/null 2>&1 || true
            echo -e "${GREEN}✓${NC}  Tekton Triggers applied (retry)"
        fi
    fi
fi
echo ""

# ── Wait for ALL components in parallel ───────────────────────────────────────
echo -e "   ${YELLOW}⏳${NC} Waiting for all components to be ready..."
WAIT_PIDS=()

# Always wait for Pipelines controller + webhook
(kubectl wait deployment/tekton-pipelines-controller deployment/tekton-pipelines-webhook \
    -n "$TEKTON_NS" --for=condition=available --timeout="${TEKTON_READY_TIMEOUT}s" &>/dev/null && \
    echo -e "${GREEN}✓${NC}  Tekton Pipelines ready" || \
    echo -e "${YELLOW}→${NC}  Tekton Pipelines not ready after ${TEKTON_READY_TIMEOUT}s, continuing...") &
WAIT_PIDS+=($!)

if [ "$INSTALL_DASHBOARD" = true ]; then
    (kubectl wait deployment/tekton-dashboard \
        -n "$TEKTON_NS" --for=condition=available --timeout="${TEKTON_READY_TIMEOUT}s" &>/dev/null && \
        echo -e "${GREEN}✓${NC}  Tekton Dashboard ready" || \
        echo -e "${YELLOW}→${NC}  Tekton Dashboard not ready after ${TEKTON_READY_TIMEOUT}s, continuing...") &
    WAIT_PIDS+=($!)
fi

if [ "$INSTALL_TRIGGERS" = true ]; then
    (kubectl wait deployment/tekton-triggers-controller deployment/tekton-triggers-webhook \
        -n "$TEKTON_NS" --for=condition=available --timeout="${TEKTON_READY_TIMEOUT}s" &>/dev/null && \
        echo -e "${GREEN}✓${NC}  Tekton Triggers ready" || \
        echo -e "${YELLOW}→${NC}  Tekton Triggers not ready after ${TEKTON_READY_TIMEOUT}s, continuing...") &
    WAIT_PIDS+=($!)
fi

for pid in "${WAIT_PIDS[@]}"; do
    wait "$pid"
done
echo ""

# ── Start kubectl proxy for Dashboard access ─────────────────────────────────────
if [ "$TEKTON_INSTALL_DASHBOARD" = true ]; then
    echo "🔗 Starting kubectl proxy for Dashboard access → http://localhost:${TEKTON_PROXY_PORT}"
    mkdir -p "$LOG_DIR"
    PROXY_PID_FILE="$LOG_DIR/kubectl-proxy.pid"
    PROXY_LOG="$LOG_DIR/kubectl-proxy.log"

    # Kill any existing proxy
    if [ -f "$PROXY_PID_FILE" ]; then
        OLD_PID=$(cat "$PROXY_PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
        rm -f "$PROXY_PID_FILE"
    fi

    # Kill any stray kubectl proxy processes on the port
    pkill -f "kubectl proxy.*port=${TEKTON_PROXY_PORT}" 2>/dev/null || true

    # Start kubectl proxy in background
    kubectl proxy --port="${TEKTON_PROXY_PORT}" >> "$PROXY_LOG" 2>&1 &
    echo $! > "$PROXY_PID_FILE"

    # Wait up to 5s for the proxy to be ready
    PROXY_READY=false
    for i in 1 2 3 4 5; do
        sleep 1
        if curl -s -o /dev/null -w "%{http_code}" \
            "http://localhost:${TEKTON_PROXY_PORT}" 2>/dev/null | grep -qE "200|400"; then
            PROXY_READY=true
            break
        fi
    done

    if [ "$PROXY_READY" = true ]; then
        echo -e "${GREEN}✓${NC}  kubectl proxy running (PID: $(cat "$PROXY_PID_FILE"))"
        echo -e "   ${BLUE}ℹ${NC}  Dashboard URL:"
        echo -e "      http://localhost:${TEKTON_PROXY_PORT}/api/v1/namespaces/${PIPELINE_NS}/services/tekton-dashboard:${TEKTON_DASHBOARD_PORT}/proxy/"
    else
        echo -e "${YELLOW}⚠${NC}  kubectl proxy started but not yet reachable — check $PROXY_LOG"
    fi
else
    echo -e "${CYAN}↺${NC}  Dashboard skipped (TEKTON_INSTALL_DASHBOARD=false)"
fi
echo ""

# ── Apply Core Infrastructure Manifests ───────────────────────────────────────
echo "🛠  Applying core infrastructure manifests..."

# All manifests use envsubst for namespace — single variable set for all templates
ENVSUBST_VARS='${TEKTON_NS} ${PIPELINE_NS} ${PIPELINE_SA} ${REGISTRY_CLUSTER_HOST} ${REGISTRY_PORT} ${REGISTRY_USERNAME} ${REGISTRY_PASSWORD}'
export TEKTON_NS PIPELINE_NS PIPELINE_SA

# Apply all manifests through envsubst (handles namespace templating)
for manifest in \
    "$MANIFEST_DIR/namespace.yaml" \
    "$MANIFEST_DIR/serviceaccount.yaml" \
    "$MANIFEST_DIR/registry-secret.yaml" \
    "$MANIFEST_DIR/triggers/rbac.yaml" \
    "$MANIFEST_DIR/triggers/triggerbinding.yaml"; do
    if [ -f "$manifest" ]; then
        apply_template "$manifest" "$ENVSUBST_VARS" "$(basename "$manifest")"
    fi
done

echo ""
echo -e "${GREEN}✓${NC} Core infrastructure ready!"
echo ""
echo "📋 Services can now register their own pipelines using:"
echo "   ./register-service.sh <service-name> <path-to-tekton-dir>"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "================================="
echo -e "${GREEN}🎉 Infrastructure Ready!${NC}"
echo "================================="
echo ""
echo "📋 Namespace:      ${PIPELINE_NS}"
echo "   ServiceAccount: ${PIPELINE_SA}"
echo "   Registry:       ${REGISTRY_CLUSTER_HOST:-k3d-dev-infra-registry}:${REGISTRY_PORT:-5002}"
if [ "$TEKTON_INSTALL_DASHBOARD" = true ]; then
echo "   Dashboard:      http://localhost:${TEKTON_PROXY_PORT}/api/v1/namespaces/${PIPELINE_NS}/services/tekton-dashboard:${TEKTON_DASHBOARD_PORT}/proxy/"
fi
if [ "$TEKTON_LIGHTWEIGHT" = true ]; then
echo "   Mode:           lightweight (Pipelines only)"
fi
echo ""
echo "🚀 Register a service:"
echo "   ./register-service.sh <service-name> <path-to-tekton-dir>"
echo ""
