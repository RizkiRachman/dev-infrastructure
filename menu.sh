#!/bin/bash
# Interactive menu for infrastructure commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

# Help function
show_help() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║          Dev Infrastructure Interactive Menu                 ║
╚════════════════════════════════════════════════════════════╝

USAGE:
  ./menu.sh [command]

COMMANDS:
  Interactive (no args):
    ./menu.sh              # Launch interactive menu

  Direct Commands:
    --start               # Start all services
    --stop                # Stop all services
    --status              # Check status of all services
    --logs <service>      # View logs for specific service
    --start <service>     # Start individual service
    --stop <service>      # Stop individual service
    --cleanup             # Clean up all resources
    --reset               # Force stop and delete everything (hard reset)

  Help:
    -h, --help            # Show this help message

EXAMPLES:
  ./menu.sh              # Interactive menu
  ./menu.sh --start      # Start all services
  ./menu.sh --status     # Check status
  ./menu.sh --logs vault # View vault logs

SERVICES MANAGED:
  - vault      (secrets management)
  - registry   (container images — k3d managed)
  - gravitee   (API gateway)
  - tekton     (CI/CD pipelines)

EOF
}

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# Handle direct commands
if [ $# -gt 0 ]; then
    case "$1" in
        --start)
            if [ -n "$2" ]; then
                # Start individual service
                "$ROOT_DIR/scripts/start-service.sh" "$2"
            else
                # Start all services
                "$ROOT_DIR/commands/start-all.sh"
            fi
            exit 0
            ;;
        --stop)
            if [ -n "$2" ]; then
                # Stop individual service
                cd "$ROOT_DIR/orchestration"
                docker-compose stop "$2"
            else
                # Stop all services
                "$ROOT_DIR/commands/stop-all.sh"
            fi
            exit 0
            ;;
        --status)
            echo "╔════════════════════════════════════════════════════════════╗"
            echo "║          Dev Infrastructure Status Summary                 ║"
            echo "╚════════════════════════════════════════════════════════════╝"
            echo ""
            "$ROOT_DIR/commands/status-all.sh"
            echo ""
            echo "📋 Quick Actions:"
            echo "   Start all:  ./menu.sh --start"
            echo "   Stop all:   ./menu.sh --stop"
            echo "   Reset all:  ./menu.sh --reset"
            echo "   Logs:       ./menu.sh --logs <service>"
            echo ""
            exit 0
            ;;
        --logs)
            if [ -n "$2" ]; then
                "$ROOT_DIR/commands/logs-all.sh" "$2"
            else
                echo "Usage: ./menu.sh --logs <service>"
                echo "Services: vault, registry, gravitee, tekton"
                exit 1
            fi
            exit 0
            ;;
        --cleanup)
            "$ROOT_DIR/commands/reset-all.sh"
            exit 0
            ;;
        --reset)
            echo -e "${RED}⚠️  HARD RESET: This will force stop and delete EVERYTHING${NC}"
            echo -e "${RED}   This includes all containers, volumes, namespaces, clusters, and data${NC}"
            echo ""
            echo -n "Type 'RESET' to confirm: "
            read CONFIRM
            if [ "$CONFIRM" = "RESET" ]; then
                echo ""
                echo -e "${YELLOW}Deleting k3d cluster...${NC}"
                k3d cluster delete "${CLUSTER_NAME:-dev-infra}" 2>/dev/null || true
                
                echo -e "${YELLOW}Force stopping all containers...${NC}"
                cd "$ROOT_DIR/orchestration"
                docker-compose down -v --remove-orphans
                
                # Remove any remaining gravitee or registry containers
                echo -e "${YELLOW}Removing any remaining containers...${NC}"
                docker ps -a --filter "name=gravitee" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
                docker ps -a --filter "name=registry" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
                docker ps -a --filter "name=vault" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
                
                echo -e "${YELLOW}Deleting all Kubernetes namespaces...${NC}"
                kubectl delete namespace "${TEKTON_NAMESPACE:-tekton-pipelines}" "${NAMESPACE:-dev-infrastructure}" ci 2>/dev/null || true
                
                echo -e "${YELLOW}Removing dangling images...${NC}"
                docker image prune -f
                
                echo -e "${YELLOW}Removing build cache...${NC}"
                docker builder prune -f
                
                echo -e "${YELLOW}Cleaning up temporary files...${NC}"
                rm -f /tmp/k3d-config-${CLUSTER_NAME:-dev-infra} 2>/dev/null || true
                
                echo ""
                echo -e "${GREEN}✅ HARD RESET COMPLETE - Everything deleted${NC}"
                echo -e "${GREEN}   Ready for onboarding bootstrap${NC}"
            else
                echo "Cancelled"
            fi
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
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

show_menu() {
    clear
    echo "=========================================="
    echo "  Dev Infrastructure Command Menu"
    echo "=========================================="
    echo ""
    echo "  ${GREEN}[1]${NC} Start all services"
    echo "  ${RED}[2]${NC} Stop all services"
    echo "  ${BLUE}[3]${NC} Check status of all services"
    echo "  ${YELLOW}[4]${NC} View logs"
    echo "  ${GREEN}[5]${NC} Start individual service"
    echo "  ${RED}[6]${NC} Stop individual service"
    echo "  ${BLUE}[7]${NC} Docker containers status"
    echo "  ${RED}[8]${NC} Clean up (delete all resources)"
    echo "  ${BLUE}[0]${NC} Exit"
    echo ""
    echo -n "  Select option: "
}

start_individual() {
    echo ""
    echo "Available services: vault, gravitee, tekton"
    echo "  Note: registry is managed by k3d (created with the cluster)"
    echo -n "Enter service name: "
    read SERVICE
    
    case "$SERVICE" in
        vault|gravitee)
            "$ROOT_DIR/scripts/start-service.sh" "$SERVICE"
            ;;
        tekton)
            "$ROOT_DIR/services/tekton/scripts/start.sh"
            ;;
        *)
            echo "Unknown service: $SERVICE"
            ;;
    esac
}

stop_individual() {
    echo ""
    echo "Available services: vault, gravitee"
    echo "  Note: registry is managed by k3d (deleted with the cluster)"
    echo -n "Enter service name: "
    read SERVICE
    
    cd "$ROOT_DIR/orchestration"
    docker-compose stop "$SERVICE"
}

view_logs() {
    echo ""
    echo "Available services: vault, gravitee, tekton"
    echo "  Note: registry logs are available via: docker logs k3d-${CLUSTER_NAME:-dev-infra}-registry"
    echo -n "Enter service name: "
    read SERVICE
    
    "$SCRIPT_DIR/logs-all.sh" "$SERVICE"
}

while true; do
    show_menu
    read -r OPTION
    
    case $OPTION in
        1)
            echo ""
            "$SCRIPT_DIR/start-all.sh"
            echo ""
            echo -n "Press Enter to continue..."
            read
            ;;
        2)
            echo ""
            "$SCRIPT_DIR/stop-all.sh"
            echo ""
            echo -n "Press Enter to continue..."
            read
            ;;
        3)
            echo ""
            "$SCRIPT_DIR/status-all.sh"
            echo ""
            echo -n "Press Enter to continue..."
            read
            ;;
        4)
            view_logs
            ;;
        5)
            start_individual
            echo ""
            echo -n "Press Enter to continue..."
            read
            ;;
        6)
            stop_individual
            echo ""
            echo -n "Press Enter to continue..."
            read
            ;;
        7)
            echo ""
            cd "$ROOT_DIR/orchestration"
            docker-compose ps
            echo ""
            echo -n "Press Enter to continue..."
            read
            ;;
        8)
            echo ""
            "$ROOT_DIR/commands/reset-all.sh"
            echo ""
            echo -n "Press Enter to continue..."
            read
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo ""
            echo -e "${RED}Invalid option${NC}"
            echo ""
            echo -n "Press Enter to continue..."
            read
            ;;
    esac
done
