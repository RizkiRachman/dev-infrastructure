#!/bin/bash
# Registry Helper Script
# Manage Docker Registry via CLI commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

REGISTRY_HOST="localhost"
REGISTRY_PORT="${REGISTRY_PORT:-5002}"
REGISTRY_URL="http://${REGISTRY_HOST}:${REGISTRY_PORT}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Help function
show_help() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║              Docker Registry CLI Helper                      ║
╚════════════════════════════════════════════════════════════╝

USAGE:
  ./registry.sh [command] [options]

COMMANDS:
  --catalog              List all repositories
  --tags <repo>          List tags for a specific repository
  --push <image:tag>     Push an image to the registry
  --pull <image:tag>     Pull an image from the registry
  --delete <repo> <tag>  Delete a specific image tag
  --status               Check registry status
  -h, --help            Show this help message

EXAMPLES:
  ./registry.sh --catalog                    # List all repositories
  ./registry.sh --tags myapp                # List tags for myapp
  ./registry.sh --push myapp:v1             # Push myapp:v1
  ./registry.sh --pull myapp:v1             # Pull myapp:v1
  ./registry.sh --delete myapp v1           # Delete myapp:v1
  ./registry.sh --status                    # Check if registry is running

EOF
}

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# Check if registry is running
check_registry() {
    if ! curl -s -o /dev/null -w "%{http_code}" "${REGISTRY_URL}/v2/" | grep -q "200"; then
        echo -e "${RED}❌ Registry not accessible at ${REGISTRY_URL}${NC}"
        echo "Make sure the registry is running: ./scripts/start-service.sh registry"
        exit 1
    fi
}

# Command: catalog
if [ "$1" = "--catalog" ]; then
    check_registry
    echo -e "${BLUE}📦 Catalog:${NC}"
    curl -s "${REGISTRY_URL}/v2/_catalog" | python3 -m json.tool 2>/dev/null || curl -s "${REGISTRY_URL}/v2/_catalog"
    exit 0
fi

# Command: tags
if [ "$1" = "--tags" ]; then
    if [ -z "$2" ]; then
        echo -e "${RED}Error: Repository name required${NC}"
        echo "Usage: ./registry.sh --tags <repository>"
        exit 1
    fi
    check_registry
    echo -e "${BLUE}🏷️  Tags for $2:${NC}"
    curl -s "${REGISTRY_URL}/v2/$2/tags/list" | python3 -m json.tool 2>/dev/null || curl -s "${REGISTRY_URL}/v2/$2/tags/list"
    exit 0
fi

# Command: push
if [ "$1" = "--push" ]; then
    if [ -z "$2" ]; then
        echo -e "${RED}Error: Image tag required${NC}"
        echo "Usage: ./registry.sh --push <image:tag>"
        exit 1
    fi
    
    IMAGE="$2"
    REPO_NAME=$(echo "$IMAGE" | cut -d: -f1)
    TAG=$(echo "$IMAGE" | cut -d: -f2)
    
    echo -e "${BLUE}📤 Pushing $IMAGE to registry...${NC}"
    
    # Tag for local registry
    docker tag "$IMAGE" "${REGISTRY_URL}/${REPO_NAME}:${TAG}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to tag image${NC}"
        exit 1
    fi
    
    # Push to registry
    docker push "${REGISTRY_URL}/${REPO_NAME}:${TAG}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully pushed ${REGISTRY_URL}/${REPO_NAME}:${TAG}${NC}"
    else
        echo -e "${RED}❌ Failed to push image${NC}"
        exit 1
    fi
    exit 0
fi

# Command: pull
if [ "$1" = "--pull" ]; then
    if [ -z "$2" ]; then
        echo -e "${RED}Error: Image tag required${NC}"
        echo "Usage: ./registry.sh --pull <image:tag>"
        exit 1
    fi
    
    IMAGE="$2"
    REPO_NAME=$(echo "$IMAGE" | cut -d: -f1)
    TAG=$(echo "$IMAGE" | cut -d: -f2)
    
    echo -e "${BLUE}📥 Pulling $IMAGE from registry...${NC}"
    docker pull "${REGISTRY_URL}/${REPO_NAME}:${TAG}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully pulled ${REGISTRY_URL}/${REPO_NAME}:${TAG}${NC}"
        # Also tag it back to the original name
        docker tag "${REGISTRY_URL}/${REPO_NAME}:${TAG}" "${REPO_NAME}:${TAG}"
    else
        echo -e "${RED}❌ Failed to pull image${NC}"
        exit 1
    fi
    exit 0
fi

# Command: delete
if [ "$1" = "--delete" ]; then
    if [ -z "$2" ] || [ -z "$3" ]; then
        echo -e "${RED}Error: Repository and tag required${NC}"
        echo "Usage: ./registry.sh --delete <repository> <tag>"
        exit 1
    fi
    
    REPO="$2"
    TAG="$3"
    
    check_registry
    
    echo -e "${YELLOW}⚠️  Deleting $REPO:$TAG...${NC}"
    
    # Get digest
    DIGEST=$(curl -s -I -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "${REGISTRY_URL}/v2/$REPO/manifests/$TAG" | grep Docker-Content-Digest | awk '{print $2}' | tr -d '\r')
    
    if [ -z "$DIGEST" ]; then
        echo -e "${RED}❌ Failed to get digest for $REPO:$TAG${NC}"
        exit 1
    fi
    
    # Delete manifest
    curl -X DELETE "${REGISTRY_URL}/v2/$REPO/manifests/$DIGEST"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully deleted $REPO:$TAG${NC}"
    else
        echo -e "${RED}❌ Failed to delete image${NC}"
        exit 1
    fi
    exit 0
fi

# Command: status
if [ "$1" = "--status" ]; then
    echo -e "${BLUE}📊 Registry Status:${NC}"
    echo -n "   URL: ${REGISTRY_URL} "
    
    if curl -s -o /dev/null -w "%{http_code}" "${REGISTRY_URL}/v2/" | grep -q "200"; then
        echo -e "${GREEN}✅ Running${NC}"
    else
        echo -e "${RED}❌ Not accessible${NC}"
    fi
    exit 0
fi

# No command provided
echo -e "${RED}Error: No command provided${NC}"
echo ""
show_help
exit 1
