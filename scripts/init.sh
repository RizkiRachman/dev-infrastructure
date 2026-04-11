#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

# Project configuration
CLUSTER_NAME="${CLUSTER_NAME:-dev-infra}"
NAMESPACE="${NAMESPACE:-dev-infrastructure}"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if k3d is installed
check_k3d() {
    if ! command -v k3d &> /dev/null; then
        print_error "k3d is not installed. Please install it first."
        print_info "Visit: https://k3d.io/#installation"
    fi
    print_success "k3d is installed"
}

# Function to check if kubectl is installed
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install it first."
        print_info "Visit: https://kubernetes.io/docs/tasks/tools/"
    fi
    print_success "kubectl is installed"
}

# Function to create k3d cluster with built-in registry
create_cluster() {
    print_info "Creating k3d cluster: $CLUSTER_NAME"
    
    if k3d cluster list | grep -q "^$CLUSTER_NAME"; then
        print_warning "Cluster '$CLUSTER_NAME' already exists"
        read -p "Do you want to delete and recreate it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deleting existing cluster..."
            k3d cluster delete "$CLUSTER_NAME"
        else
            print_info "Using existing cluster"
            return 0
        fi
    fi
    
    # Create cluster with built-in registry (no manual containerd config needed)
    k3d cluster create "$CLUSTER_NAME" \
        --registry-create k3d-${CLUSTER_NAME}-registry:${REGISTRY_PORT:-5002} \
        --agents 0 \
        --k3s-arg "--disable=traefik@server:0"
    
    print_success "Cluster '$CLUSTER_NAME' created with built-in registry"
}

# Function to set kubectl context
set_context() {
    print_info "Setting kubectl context to $CLUSTER_NAME"
    
    # Merge k3d kubeconfig with existing kubeconfig
    K3D_CONFIG=$(k3d kubeconfig write "$CLUSTER_NAME" --output /tmp/k3d-config-$CLUSTER_NAME 2>/dev/null && echo /tmp/k3d-config-$CLUSTER_NAME)
    
    if [ -f "$HOME/.kube/config" ]; then
        KUBECONFIG=/tmp/k3d-config-$CLUSTER_NAME:$HOME/.kube/config kubectl config view --flatten > /tmp/merged-config
        mv /tmp/merged-config "$HOME/.kube/config"
    else
        mkdir -p "$HOME/.kube"
        cp /tmp/k3d-config-$CLUSTER_NAME "$HOME/.kube/config"
    fi
    
    # Set current context
    kubectl config use-context "k3d-$CLUSTER_NAME"
    
    # Clean up
    rm -f /tmp/k3d-config-$CLUSTER_NAME
    
    print_success "kubectl context set to k3d-$CLUSTER_NAME"
}

# Function to verify k3d registry is accessible
verify_registry() {
    print_info "Verifying k3d built-in registry"
    
    REGISTRY_PORT="${REGISTRY_PORT:-5002}"
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${REGISTRY_PORT}/v2/" | grep -q "200"; then
        print_success "Registry accessible at localhost:${REGISTRY_PORT}"
    else
        print_warning "Registry not yet reachable at localhost:${REGISTRY_PORT} — may take a few seconds"
    fi
}

# Function to create namespace
create_namespace() {
    print_info "Creating namespace: $NAMESPACE"
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_warning "Namespace '$NAMESPACE' already exists"
    else
        kubectl create namespace "$NAMESPACE"
        print_success "Namespace '$NAMESPACE' created"
    fi
    
    # Set as default namespace for the context
    kubectl config set-context --current --namespace="$NAMESPACE"
    print_success "Default namespace set to $NAMESPACE"
}

# Function to configure RBAC
configure_rbac() {
    print_info "Configuring RBAC for resource protection"
    
    # Create RBAC manifests directory if not exists
    RBAC_DIR="services/tekton/manifests/rbac"
    mkdir -p "$RBAC_DIR"
    
    # Create Role for dev-infrastructure namespace
    cat > "$RBAC_DIR/namespace-role.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dev-infra-admin
  namespace: $NAMESPACE
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
EOF
    
    # Create RoleBinding for the current user
    cat > "$RBAC_DIR/namespace-rolebinding.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-infra-admin-binding
  namespace: $NAMESPACE
subjects:
- kind: User
  name: $(kubectl config view --minify -o jsonpath='{.contexts[0].context.user}')
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: dev-infra-admin
  apiGroup: rbac.authorization.k8s.io
EOF
    
    # Apply RBAC
    kubectl apply -f "$RBAC_DIR/namespace-role.yaml"
    kubectl apply -f "$RBAC_DIR/namespace-rolebinding.yaml"
    
    print_success "RBAC configured for namespace $NAMESPACE"
}

# Function to deploy Tekton
deploy_tekton() {
    print_info "Deploying Tekton pipelines"
    
    # Check if Tekton namespace exists
    TEKTON_NS="${TEKTON_NAMESPACE:-tekton-pipelines}"
    if ! kubectl get namespace "$TEKTON_NS" &> /dev/null; then
        print_info "Creating $TEKTON_NS namespace"
        kubectl create namespace "$TEKTON_NS"
    fi
    
    # Apply Tekton manifests
    TEKTON_DIR="services/tekton/manifests"
    if [ -d "$TEKTON_DIR" ]; then
        print_info "Applying Tekton manifests from $TEKTON_DIR"
        export TEKTON_NS="${TEKTON_NAMESPACE:-tekton-pipelines}"
        export PIPELINE_NS="${PIPELINE_NAMESPACE:-tekton-pipelines}"
        export PIPELINE_SA="${PIPELINE_SERVICE_ACCOUNT:-tekton-sa}"
        ENVSUBST_VARS='${TEKTON_NS} ${PIPELINE_NS} ${PIPELINE_SA} ${REGISTRY_CLUSTER_HOST} ${REGISTRY_PORT} ${REGISTRY_USERNAME} ${REGISTRY_PASSWORD}'
        if [ -f "$TEKTON_DIR/namespace.yaml" ]; then
            envsubst "$ENVSUBST_VARS" < "$TEKTON_DIR/namespace.yaml" | kubectl apply -f -
        fi
        if [ -f "$TEKTON_DIR/registry-secret.yaml" ]; then
            envsubst "$ENVSUBST_VARS" < "$TEKTON_DIR/registry-secret.yaml" | kubectl apply -f -
        fi
        if [ -f "$TEKTON_DIR/serviceaccount.yaml" ]; then
            envsubst "$ENVSUBST_VARS" < "$TEKTON_DIR/serviceaccount.yaml" | kubectl apply -f -
        fi
        if [ -f "$TEKTON_DIR/triggers/rbac.yaml" ]; then
            envsubst "$ENVSUBST_VARS" < "$TEKTON_DIR/triggers/rbac.yaml" | kubectl apply -f -
        fi
        if [ -f "$TEKTON_DIR/triggers/triggerbinding.yaml" ]; then
            envsubst "$ENVSUBST_VARS" < "$TEKTON_DIR/triggers/triggerbinding.yaml" | kubectl apply -f -
        fi
        print_success "Tekton manifests applied"
    else
        print_warning "Tekton manifests directory not found: $TEKTON_DIR"
    fi
}

# Function to check cluster status
check_status() {
    print_info "Cluster Status:"
    echo ""
    
    print_info "k3d clusters:"
    k3d cluster list
    echo ""
    
    print_info "Current kubectl context:"
    kubectl config current-context
    echo ""
    
    print_info "Namespaces:"
    kubectl get namespaces
    echo ""
    
    print_info "Pods in $NAMESPACE:"
    kubectl get pods -n "$NAMESPACE" 2>/dev/null || print_warning "No pods found or namespace doesn't exist"
}

# Function to display menu
show_menu() {
    echo ""
    echo "=========================================="
    echo "  Dev-Infrastructure Initialization Menu"
    echo "=========================================="
    echo ""
    echo "1) Create/Recreate k3d Cluster (with built-in registry)"
    echo "2) Set kubectl Context"
    echo "3) Verify Registry"
    echo "4) Create Namespace"
    echo "5) Configure RBAC"
    echo "6) Deploy Tekton"
    echo "7) Setup All (1-6)"
    echo "8) Check Status"
    echo "9) Exit"
    echo ""
    echo -n "Select an option [1-9]: "
}

# Main script
main() {
    print_info "Dev-Infrastructure Initialization Script"
    check_k3d
    check_kubectl
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                create_cluster
                ;;
            2)
                set_context
                ;;
            3)
                verify_registry
                ;;
            4)
                create_namespace
                ;;
            5)
                configure_rbac
                ;;
            6)
                deploy_tekton
                ;;
            7)
                print_info "Running full setup..."
                create_cluster
                set_context
                verify_registry
                create_namespace
                configure_rbac
                deploy_tekton
                print_success "Full setup completed!"
                ;;
            8)
                check_status
                ;;
            9)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-9."
                ;;
        esac
    done
}

# Run main function
main
