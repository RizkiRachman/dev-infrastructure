# Dev Infrastructure

Local development stack with self-hosted CI/CD, registry, secrets, and API gateway.

## Table of Contents

- [What's Inside](#whats-inside)
- [Quick Start](#quick-start-5-minutes)
  - [Prerequisites](#1-prerequisites)
  - [Start Everything](#2-start-everything)
  - [Access Services](#3-access-services)
  - [Tekton Infrastructure](#4-tekton-infrastructure)
  - [Check Status](#5-check-status)
- [Start Individual Services](#start-individual-services)
- [Quick Commands](#quick-commands)
- [Project Layout](#project-layout)
- [Requirements](#requirements)
- [Additional Documentation](#additional-documentation)

## What's Inside

| Service | Purpose | URL (default) |
|---------|---------|---------------|
| **Registry** | Store container images (k3d managed) | http://localhost:5002 |
| **Vault** | Manage secrets | http://localhost:8201 |
| **Gravitee** | Route APIs | http://localhost:8084 |
| **Tekton** | CI/CD infrastructure (lightweight or full) | http://localhost:8001/api/v1/namespaces/tekton-pipelines/services/tekton-dashboard:9097/proxy/ |

*All ports are configurable via `.env` file*

## Quick Start (5 minutes)

### 1. Prerequisites

**Docker** (Required for container runtime)
```bash
# macOS
brew install --cask docker
# Start Docker Desktop app
# Settings → Resources → set CPUs: 4, Memory: 8GB

# Linux
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

**k3d** (Creates lightweight Kubernetes clusters with built-in registry)
```bash
# macOS
brew install k3d

# Linux
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

**Required tools:**
```bash
brew install kubectl gettext   # macOS
# or
sudo apt install kubectl gettext  # Linux
```

**Configuration:**
- All ports and settings are configurable via `.env` file
- Copy `.env.example` to `.env` and customize as needed
- No hardcoded values in scripts - everything uses environment variables

### 2. Start Everything

```bash
cp .env.example .env
./scripts/init.sh
```

The `scripts/init.sh` script provides an interactive menu to set up the dev-infrastructure:

**Menu Options:**
1. **Create/Recreate k3d Cluster** - Creates the local Kubernetes cluster with built-in registry
2. **Set kubectl Context** - Configures kubectl to use the dev-infra cluster
3. **Verify Registry** - Checks that the k3d built-in registry is accessible
4. **Create Namespace** - Creates the dedicated `dev-infrastructure` namespace
5. **Configure RBAC** - Sets up Role-Based Access Control for resource protection
6. **Deploy Tekton** - Deploys Tekton pipelines and related resources
7. **Setup All** - Runs steps 1-6 in sequence for complete initialization
8. **Check Status** - Displays cluster, context, and namespace status
9. **Exit** - Exits the script

**Quick Full Setup:**
```bash
./scripts/init.sh
# Select option 6 for full setup
```

### 3. Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Registry | http://localhost:5002 | (no auth required) |
| Vault | http://localhost:8201 | dev-root-token |
| Gravitee | http://localhost:8084 | admin / admin |

**Registry Management:**
```bash
# Use the helper script
./registry.sh --catalog              # List all repositories
./registry.sh --tags myapp          # List tags for myapp
./registry.sh --push myapp:v1       # Push an image
./registry.sh --pull myapp:v1       # Pull an image
./registry.sh --delete myapp v1     # Delete an image
./registry.sh --status             # Check registry status

# Or use direct commands
curl http://localhost:5002/v2/_catalog
docker tag myapp:v1 localhost:5002/myapp:v1
docker push localhost:5002/myapp:v1
```

### 4. Tekton Infrastructure

Start Tekton CI/CD infrastructure. Two modes available:

**Full mode** (default) — Pipelines + Dashboard + Triggers (5 pods):
```bash
./services/tekton/scripts/start.sh
```

**Lightweight mode** — Pipelines only (2 pods, faster startup):
```bash
# Set in .env or export before running
TEKTON_LIGHTWEIGHT=true ./services/tekton/scripts/start.sh
```

This installs:
- **Tekton Pipelines** in `${TEKTON_NAMESPACE}` namespace (shared across all services)
- **Tekton Dashboard** via kubectl proxy at http://localhost:${TEKTON_PROXY_PORT}/... (optional, skipped in lightweight mode)
- **Tekton Triggers** for webhook automation (optional, skipped in lightweight mode)
- **Infrastructure manifests** — namespace, serviceaccount, RBAC, registry secret

Individual components can also be toggled via `.env`:
- `TEKTON_INSTALL_DASHBOARD=true/false`
- `TEKTON_INSTALL_TRIGGERS=true/false`

Services then register their pipelines and tasks:
```bash
cd ../goods-price-comparison-service/ci/local
./setup.sh
```

### 5. Check Status

```bash
./scripts/status.sh
kubectl get pods -n ci
```

## Documentation & Contributing

- [Setup Guide](docs/SETUP.md) - Detailed installation and configuration
- [Architecture](docs/ARCHITECTURE.md) - System architecture and components
- [Contributing](docs/CONTRIBUTING.md) - How to contribute to this project
- [Security](docs/SECURITY.md) - Security policy and vulnerability reporting
- [Version History](docs/CHANGELOG.md) - Changelog and changes

## Start Individual Services

```bash
./scripts/start-service.sh vault      # Secrets only
./scripts/start-service.sh registry   # Registry status (k3d managed)
./scripts/start-service.sh gravitee   # API Gateway only
./services/tekton/scripts/start.sh    # Tekton (mode controlled by .env)
./services/tekton/scripts/stop.sh     # Stop kubectl proxy
```

## Quick Commands

```bash
./menu.sh                  # Interactive menu (from root)
./commands/start-all.sh    # Start all services
./commands/stop-all.sh     # Stop all services
./commands/status-all.sh   # Check status of all services
./commands/logs-all.sh <svc> # View logs for specific service
./registry.sh --catalog    # List registry repositories
```

## Project Layout

```
.
├── menu.sh          # Interactive menu for all operations
├── commands/        # Quick commands for centralized execution
├── scripts/         # Start/status/logs helpers
├── orchestration/   # Docker compose files
├── services/        # Each tool's config
│   ├── tekton/      # Tekton infrastructure (lightweight or full mode)
│   ├── vault/
│   ├── quay/
│   └── gravitee/
└── docs/            # Detailed guides
```

## Requirements

- Docker Desktop or Docker Engine
- k3d (lightweight Kubernetes)
- docker-compose
- kubectl
- gettext (envsubst)
- 8GB RAM
- ~20GB disk space

See [Setup Guide](docs/SETUP.md) for detailed setup instructions.
