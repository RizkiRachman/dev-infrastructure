# Vault Policy for Development Environment
# Provides appropriate permissions for CI/CD workflows

# Allow read access to secrets under dev/
path "secret/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow read access to CI secrets
path "secret/data/ci/*" {
  capabilities = ["read", "list"]
}

# Allow access to local/infrastructure secrets
path "local/infrastructure/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "local/infrastructure/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

# Allow managing kv v2 metadata
path "secret/metadata/dev/*" {
  capabilities = ["list", "read", "delete"]
}

# Allow token operations
path "auth/token/create" {
  capabilities = ["create", "update"]
}

# Allow checking token capabilities
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# Allow reading system health
path "sys/health" {
  capabilities = ["read"]
}

# Transit engine for encryption (optional)
path "transit/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
