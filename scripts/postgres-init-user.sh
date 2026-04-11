#!/bin/bash
# Manually create PostgreSQL superuser and push credentials to Vault
# Use this if PostgreSQL was already initialized before the init script was added

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

# Get project name for user name
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dev-infra}"
PROJECT_NAME="${PROJECT_NAME//-/_}"  # Replace dashes with underscores for PostgreSQL user

# Generate random password (32 characters)
GENERATED_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

echo "Creating PostgreSQL superuser: $PROJECT_NAME"

# Create superuser with generated password
docker exec -i postgres psql -U postgres -d postgres <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$PROJECT_NAME') THEN
            CREATE USER "$PROJECT_NAME" WITH PASSWORD '$GENERATED_PASSWORD' SUPERUSER CREATEDB;
            GRANT ALL PRIVILEGES ON DATABASE postgres TO "$PROJECT_NAME";
            RAISE NOTICE 'User % created', '$PROJECT_NAME';
        ELSE
            RAISE NOTICE 'User % already exists', '$PROJECT_NAME';
        END IF;
    END
    \$\$;
EOSQL

echo "✓ Superuser created/verified: $PROJECT_NAME"

# Push credentials to Vault
if [ -n "$VAULT_ADDR" ] && [ -n "$VAULT_TOKEN" ]; then
    echo "Pushing credentials to Vault..."
    curl -sf -X POST "${VAULT_ADDR}/v1/local/infrastructure/data/database" \
        -H "X-Vault-Token: ${VAULT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"data\": {
            \"POSTGRES_HOST\": \"localhost\",
            \"POSTGRES_PORT\": \"${POSTGRES_PORT:-5432}\",
            \"POSTGRES_USER\": \"${PROJECT_NAME}\",
            \"POSTGRES_PASSWORD\": \"${GENERATED_PASSWORD}\",
            \"POSTGRES_DB\": \"postgres\"
        }}" >/dev/null 2>&1 && \
        echo "✓ Credentials stored in Vault: local/infrastructure/data/database" || \
        echo "⚠ Warning: Failed to store credentials in Vault"
else
    echo "⚠ Warning: VAULT_ADDR or VAULT_TOKEN not set — credentials not stored in Vault"
    echo "   Generated password: $GENERATED_PASSWORD"
fi

echo "Done."
