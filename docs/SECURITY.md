# Security Policy

## Supported Versions

This project is actively maintained. Security updates will be provided for the current version.

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly.

**Do not** open a public issue.

Instead, send an email to: [SECURITY EMAIL PLACEHOLDER]

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if known)

## Security Best Practices

### For Development

- **Never commit secrets**: Never commit `.env` files or any secrets to the repository
- **Use environment variables**: All sensitive data should be in environment variables
- **Review dependencies**: Regularly update Docker images and dependencies
- **Default credentials**: Change default passwords before deploying to production

### For Production Deployment

- **Change default credentials**: Update all default passwords in `.env`
- **Enable authentication**: Configure Vault authentication for production
- **Network isolation**: Run services in isolated networks
- **TLS/SSL**: Enable TLS for all services in production
- **Regular updates**: Keep Docker images and dependencies updated

### Known Development-Only Features

The following features are **not secure** for production use:

- **Registry**: No authentication, no encryption
- **Vault**: Uses dev-root-token (change for production)
- **Gravitee**: Default admin/admin credentials (change for production)
- **Docker networks**: Default configuration for local development

### Secrets Management

- Use HashiCorp Vault for secrets storage
- Never store secrets in code or configuration files
- Rotate credentials regularly
- Use different credentials for development, staging, and production

## Dependency Security

This project uses the following dependencies:

- Docker containers (various official images)
- Kubernetes (via Docker Desktop or Rancher Desktop)
- Tekton components
- HashiCorp Vault

Keep these updated and review security advisories regularly.

## Security Audits

This project is designed for local development. For production use:
- Conduct security audits before deployment
- Use production-grade alternatives where needed
- Implement proper authentication and authorization
- Enable logging and monitoring
- Set up intrusion detection

## Contact

For security-related questions or concerns, please contact: [SECURITY EMAIL PLACEHOLDER]
