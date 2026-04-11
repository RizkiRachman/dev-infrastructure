# Vault Server Configuration - Dev Infrastructure
# Uses file storage backend so data persists across container restarts.
# NOT for production use.

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address     = "0.0.0.0:8201"
  tls_disable = "true"
}

api_addr = "http://0.0.0.0:8201"
ui       = true

default_lease_ttl = "168h"
max_lease_ttl     = "720h"
