# Setup Guide

## Install

### macOS

```bash
# Install Docker Desktop (includes Docker + Kubernetes)
brew install --cask docker
# Start Docker Desktop app
# Settings → Resources → set CPUs: 4, Memory: 8GB
# Settings → Kubernetes → Enable Kubernetes

# Install kubectl
brew install kubectl

# Install docker-compose
brew install docker-compose
```

### Linux (Ubuntu/Debian)

```bash
sudo apt install docker docker-compose kubectl
# Enable Kubernetes in Docker Desktop or use Rancher Desktop
```

### Alternative: Rancher Desktop

```bash
# Download from https://rancherdesktop.io/
# Select container runtime: dockerd (moby)
# Enable Kubernetes
```

## First Run

```bash
cd /path/to/dev-infrastructure
cp .env.example .env
./scripts/init.sh
```

Wait 2-3 minutes for startup. Then access:
- http://localhost:5002 - Docker Registry (CLI only)
- http://localhost:8201 - Vault (dev-root-token)
- http://localhost:8084 - Gravitee (admin/admin)

**Start Tekton CI/CD** (requires Kubernetes + kubectl):
```bash
# Full mode (default): Pipelines + Dashboard + Triggers
./services/tekton/scripts/start.sh
# Then access: http://localhost:8001/api/v1/namespaces/tekton-pipelines/services/tekton-dashboard:9097/proxy/

# Lightweight mode: Pipelines only (2 pods, faster)
TEKTON_LIGHTWEIGHT=true ./services/tekton/scripts/start.sh
```

## Common Commands

```bash
# Start all services
./commands/start-all.sh

# Stop all services
./commands/stop-all.sh

# Check status of all services
./commands/status-all.sh

# View logs
./commands/logs-all.sh vault
./commands/logs-all.sh gravitee

# Registry management
./registry.sh --catalog              # List repositories
./registry.sh --tags <repo>          # List tags
./registry.sh --push <image:tag>     # Push image
./registry.sh --pull <image:tag>     # Pull image

# Interactive menu
./menu.sh
```

## Configuration

All configuration is centralized in the root `.env` file:
- All ports are configurable
- No hardcoded values in scripts
- No duplicate .env files in children folders

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_PORT` | 8201 | Vault UI/API port |
| `REGISTRY_PORT` | 5002 | Container registry port |
| `GRAVITEE_MGMT_UI_PORT` | 8084 | Gravitee management UI port |
| `TEKTON_DASHBOARD_PORT` | 9097 | Dashboard service port (internal) |
| `TEKTON_PROXY_PORT` | 8001 | kubectl proxy port (for dashboard access) |
| `TEKTON_NAMESPACE` | tekton-pipelines | Tekton shared namespace |
| `PIPELINE_NAMESPACE` | tekton-pipelines | Service pipelines namespace |
| `PIPELINE_SERVICE_ACCOUNT` | tekton-sa | Pipeline service account name |
| `TEKTON_LIGHTWEIGHT` | false | Lightweight mode (Pipelines only) |
| `TEKTON_INSTALL_DASHBOARD` | true | Install Dashboard component |
| `TEKTON_INSTALL_TRIGGERS` | true | Install Triggers component |
| `TEKTON_READY_TIMEOUT` | 180 | Max seconds to wait per component |
| `TEKTON_PIPELINE_RELEASE_URL` | (latest) | Pipeline release manifest URL |
| `TEKTON_DASHBOARD_RELEASE_URL` | (latest) | Dashboard release manifest URL |
| `TEKTON_TRIGGERS_RELEASE_URL` | (latest) | Triggers release manifest URL |

## Registry Usage

The registry is managed via CLI commands (no web UI):

```bash
# List all repositories
./registry.sh --catalog

# List tags for a repository
./registry.sh --tags myapp

# Push an image
./registry.sh --push myapp:v1

# Pull an image
./registry.sh --pull myapp:v1

# Delete an image
./registry.sh --delete myapp v1
```

Or use direct Docker commands:
```bash
curl http://localhost:5002/v2/_catalog
docker tag myapp:v1 localhost:5002/myapp:v1
docker push localhost:5002/myapp:v1
```
