#!/bin/bash
# Stop Tekton Infrastructure
# Stops the kubectl proxy only — all Kubernetes resources are preserved.
# Use reset.sh (or commands/reset-all.sh) to delete namespaces and wipe resources.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$(dirname "$SERVICE_DIR")")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

TEKTON_INSTALL_DASHBOARD="${TEKTON_INSTALL_DASHBOARD:-true}"
TEKTON_LIGHTWEIGHT="${TEKTON_LIGHTWEIGHT:-false}"
TEKTON_PROXY_PORT="${TEKTON_PROXY_PORT:-8001}"
if [ "$TEKTON_LIGHTWEIGHT" = true ]; then
    TEKTON_INSTALL_DASHBOARD=false
fi

LOG_DIR="$ROOT_DIR/logs"

echo "🛑 Stopping Tekton Infrastructure..."
echo ""

# Stop kubectl proxy (only if dashboard was installed)
if [ "$TEKTON_INSTALL_DASHBOARD" = true ]; then
    PROXY_PID_FILE="$LOG_DIR/kubectl-proxy.pid"
    if [ -f "$PROXY_PID_FILE" ]; then
        PID=$(cat "$PROXY_PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null
            echo -e "${GREEN}✓${NC} kubectl proxy stopped (PID: $PID)"
        else
            echo -e "${YELLOW}→${NC} kubectl proxy was not running"
        fi
        rm -f "$PROXY_PID_FILE"
    else
        echo -e "${YELLOW}→${NC} No kubectl proxy PID file found"
    fi

    # Also kill any stray proxy processes on the port
    pkill -f "kubectl proxy.*port=${TEKTON_PROXY_PORT}" 2>/dev/null && \
        echo -e "${GREEN}✓${NC} Stray kubectl proxy processes cleaned up" || true
else
    echo -e "${YELLOW}→${NC} Dashboard not installed (TEKTON_INSTALL_DASHBOARD=false)"
fi

echo ""
echo -e "${GREEN}✓${NC} Tekton stopped. All Kubernetes resources preserved."
echo "   Restart anytime with: $SCRIPT_DIR/start.sh"
echo "   To wipe all resources: $ROOT_DIR/commands/reset-all.sh"
