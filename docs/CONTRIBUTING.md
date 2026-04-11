# Contributing to Dev Infrastructure

Thank you for your interest in contributing to this project! This document provides guidelines for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/your-username/dev-infrastructure.git
   cd dev-infrastructure
   ```
3. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Prerequisites

- Docker Desktop (with Kubernetes enabled) or Rancher Desktop
- kubectl
- docker-compose
- Bash shell (Linux/macOS)

## Development Workflow

1. **Make your changes**
   - Edit configuration in `.env.example` (not `.env`)
   - Update documentation if needed
   - Ensure all scripts are executable (`chmod +x *.sh`)

2. **Test your changes**
   ```bash
   cp .env.example .env
   ./scripts/init.sh
   ./commands/status-all.sh
   ```

3. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```

4. **Push and create a Pull Request**
   ```bash
   git push origin feature/your-feature-name
   ```

## Code Style

- Use Bash for scripts
- Add help flags (`-h`, `--help`) to all command-line tools
- Use environment variables for configuration (no hardcoded values)
- Document all scripts with header comments
- Follow existing naming conventions

## Configuration

- All ports and settings must be configurable via `.env` file
- No hardcoded values in scripts or configuration files
- Use `${VARIABLE:-default}` syntax for defaults
- All configuration must be centralized in root `.env.example`

## Documentation

- Update README.md for user-facing changes
- Update docs/ARCHITECTURE.md for structural changes
- Update docs/SETUP.md for installation changes
- Add comments to complex code sections

## Submitting Changes

1. Ensure your code passes basic tests
2. Update documentation as needed
3. Write clear commit messages
4. Keep pull requests focused and small
5. Reference related issues in your PR description

## Project Structure

```
.
├── commands/        # Centralized command scripts
├── docs/            # Detailed documentation
├── orchestration/   # Docker compose files
├── scripts/         # Helper scripts
├── services/        # Service-specific configuration
└── .env.example     # Configuration template
```

## Questions?

Feel free to open an issue for questions or discussions before making large changes.
