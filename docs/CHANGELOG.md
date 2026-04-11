# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Interactive menu system (`menu.sh`) with direct command support
- Centralized command execution via `commands/` folder
- Registry CLI helper script (`registry.sh`) for image management
- Shared Tekton Dashboard architecture for viewing pipelines from all namespaces
- Environment variable-based configuration (no hardcoded values)
- Documentation files for public repository (CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md)
- **Tekton lightweight mode** (`TEKTON_LIGHTWEIGHT=true`) — Pipelines only (2 pods)
- **Optional Dashboard** (`TEKTON_INSTALL_DASHBOARD`) — skip dashboard + proxy
- **Optional Triggers** (`TEKTON_INSTALL_TRIGGERS`) — skip triggers when not using webhooks
- **Configurable release URLs** (`TEKTON_PIPELINE_RELEASE_URL`, `TEKTON_DASHBOARD_RELEASE_URL`, `TEKTON_TRIGGERS_RELEASE_URL`) — pin versions or use mirrors
- **Configurable ready timeout** (`TEKTON_READY_TIMEOUT`) — default 180s per component
- **kubectl proxy for Tekton Dashboard** — more stable connection than port-forward, accessed at `http://localhost:8001/api/v1/namespaces/.../proxy/`
- All Tekton manifests now use `envsubst` for namespace/SA templating (no hardcoded values)

### Changed
- Removed Registry UI (now uses CLI commands)
- Migrated from Kind cluster to k3d with built-in registry
- Centralized all configuration in root `.env` file
- Removed duplicate `.env` files from children folders
- Updated Tekton installation to use shared infrastructure approach
- Removed obsolete `version` attribute from docker-compose.yml
- **Tekton start.sh**: removed empty GCR secret, parallel waits for all components, env-based release URLs, replaced port-forward with kubectl proxy
- **Tekton stop.sh**: respects optional dashboard flag, kills kubectl proxy instead of port-forward
- **Tekton status.sh**: conditionally shows dashboard/triggers based on install flags, checks kubectl proxy instead of port-forward
- **init.sh**: uses `TEKTON_NAMESPACE` env var instead of hardcoded namespace, applies manifests via `envsubst`

### Fixed
- Network conflict issues with Docker networks
- Image pull errors by adding proper image pull secrets
- CORS configuration issues with Registry

### Removed
- Registry UI (due to persistent CORS issues)
- Kind cluster dependency (replaced by k3d)
- Backup files and unused configurations

## [0.1.0] - Initial Release

### Added
- HashiCorp Vault for secrets management
- Docker Registry for container images
- Gravitee API Gateway
- Tekton CI/CD pipelines
- Docker Compose orchestration
- Helper scripts for service management
- Initial documentation
