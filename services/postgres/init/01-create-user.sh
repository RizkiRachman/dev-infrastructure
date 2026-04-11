#!/bin/bash
# PostgreSQL Init Script
# Generates a random password, creates a superuser named after COMPOSE_PROJECT_NAME,
# and pushes credentials to Vault.
# Runs automatically on first container start (docker-entrypoint-initdb.d).

set -e

echo "PostgreSQL initialization..."

# Get project name for user name
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dev-infra}"
PROJECT_NAME="${PROJECT_NAME//-/_}"  # Replace dashes with underscores for PostgreSQL user

# Generate random password (32 characters)
GENERATED_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

echo "Creating superuser: $PROJECT_NAME"

# Create superuser with generated password
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER "$PROJECT_NAME" WITH PASSWORD '$GENERATED_PASSWORD' SUPERUSER CREATEDB;
    GRANT ALL PRIVILEGES ON DATABASE "$POSTGRES_DB" TO "$PROJECT_NAME";
EOSQL

echo "✓ Superuser created: $PROJECT_NAME"

# Push credentials to Vault
if [ -n "$VAULT_ADDR" ] && [ -n "$VAULT_TOKEN" ]; then
    echo "Pushing credentials to Vault..."
    curl -sf -X POST "${VAULT_ADDR}/v1/local/infrastructure/data/database" \
        -H "X-Vault-Token: ${VAULT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"data\": {
            \"POSTGRES_HOST\": \"${POSTGRES_HOST:-localhost}\",
            \"POSTGRES_PORT\": \"${POSTGRES_PORT:-5432}\",
            \"POSTGRES_USER\": \"${PROJECT_NAME}\",
            \"POSTGRES_PASSWORD\": \"${GENERATED_PASSWORD}\",
            \"POSTGRES_DB\": \"${POSTGRES_ADMIN_DB:-postgres}\"
        }}" >/dev/null 2>&1 && \
        echo "✓ Credentials stored in Vault: local/infrastructure/data/database" || \
        echo "⚠ Warning: Failed to store credentials in Vault"
else
    echo "⚠ Warning: VAULT_ADDR or VAULT_TOKEN not set — credentials not stored in Vault"
    echo "   Generated password: $GENERATED_PASSWORD"
fi

echo "PostgreSQL initialization complete."
