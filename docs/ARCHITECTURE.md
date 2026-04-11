# Architecture Overview

## What Runs Where

```
┌─────────────────────────────────────────────────────────────────────┐
│  Your Computer                                                      │
│                                                                     │
│  ┌──────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐               │
│  │ Registry │  │  Vault  │  │Gravitee │  │ Quay   │               │
│  │ CLI Only │  │  :8201  │  │  API GW │  │ :8080  │               │
│  │  :5002   │  │ Secrets │  │  :8084  │  │        │               │
│  └────┬─────┘  └────┬────┘  └────┬────┘  └───┬────┘               │
│       │             │            │            │                    │
│  ┌────┴─────────────┴────────────┴────────────┴────────────────┐   │
│  │              Docker Network (${INFRA_SUBNET})               │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │         MongoDB │ Elasticsearch (Gravitee deps)      │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Kubernetes Cluster (Docker Desktop / Rancher Desktop)       │   │
│  │  ┌──────────┐  ┌──────────────────────────────────────┐    │   │
│  │  │ Tekton   │  │  Dashboard (optional) :9097          │    │   │
│  │  │Pipelines │  │  Triggers (optional)                 │    │   │
│  │  │ (always) │  │  Accessed via kubectl proxy :8001     │    │   │
│  │  └──────────┘  └──────────────────────────────────────┘    │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │ Service pipelines in ${PIPELINE_NAMESPACE} (per service)│   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Service Details

| Service | What It Does | Dependencies |
|---------|--------------|--------------|
| **Vault** | Store passwords, API keys, certificates | None |
| **Registry** | Host Docker images (simple, CLI only) | None |
| **PostgreSQL** | Shared database for all services | None |
| **Gravitee** | API routing, rate limiting, auth | MongoDB, Elasticsearch |
| **Tekton** | CI/CD pipelines (lightweight or full mode) | Kubernetes, kubectl |

## Data Storage

All data survives container restarts:
- **Vault**: `vault-data` volume (encrypted)
- **Registry**: `registry-data` volume
- **Gravitee**: `gravitee-mongo` + `gravitee-elasticsearch` volumes
- **Tekton**: Kubernetes PVC (`tekton-workspace-pvc`)

## Networks

- `dev-infra`: Main Docker network for all core services
- `vault-backend`: Isolated Vault access only
- Kubernetes cluster: Managed by Docker Desktop / Rancher Desktop

## Configuration

- **Centralized**: All configuration in root `.env` file
- **Environment variables**: No hardcoded values in scripts
- **Ports**: All ports configurable via `.env`
- **Services**: No duplicate .env files in children folders

## Registry Management

Registry is managed via CLI commands:
```bash
./registry.sh --catalog              # List repositories
./registry.sh --tags <repo>          # List tags
./registry.sh --push <image:tag>     # Push image
./registry.sh --pull <image:tag>     # Pull image
```

## Tekton Architecture

- **Lightweight mode** (`TEKTON_LIGHTWEIGHT=true`): Pipelines controller + webhook only (2 pods)
- **Full mode** (default): Pipelines + optional Dashboard + optional Triggers
- **Dashboard**: Optional — controlled by `TEKTON_INSTALL_DASHBOARD`, can view pipelines from all namespaces via kubectl proxy
- **Triggers**: Optional — controlled by `TEKTON_INSTALL_TRIGGERS`, for webhook automation
- **Service Pipelines**: Each service manages its own pipelines in `${PIPELINE_NAMESPACE}`
- **All namespaces configurable** via `.env` — no hardcoded values

## Security Notes

- All containers run as standard Docker containers
- Databases are **not exposed** to host (internal only)
- Development mode uses simple passwords (not for production)
- Registry has no authentication (development only)
