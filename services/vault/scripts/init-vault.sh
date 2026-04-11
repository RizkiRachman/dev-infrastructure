#!/bin/bash
# Vault Initialization & Unseal Script
#
# State machine:
#   1. Not initialized  → vault operator init → save keys → unseal → provision
#   2. Initialized + sealed   → load .vault-keys → unseal (data already there)
#   3. Initialized + unsealed → nothing to do
#
# Keys are saved to $ROOT_DIR/.vault-keys (gitignored).
# On reset (docker-compose down -v), volumes are wiped and this starts fresh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$(dirname "$SERVICE_DIR")")"

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8201}"
VAULT_KEYS_FILE="$ROOT_DIR/.vault-keys"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

export VAULT_ADDR

echo "🔐 Vault Init/Unseal — $VAULT_ADDR"
echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────
parse_json_field() {
    local json="$1" field="$2"
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$field"
    elif command -v python3 &>/dev/null; then
        echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['$field'])"
    else
        echo "$json" | grep -o "\"${field}\":\"[^\"]*\"" | cut -d'"' -f4
    fi
}

vault_get() {
    curl -sf "${VAULT_ADDR}/v1/${1}" \
        -H "X-Vault-Token: ${VAULT_TOKEN}" \
        -H "Content-Type: application/json"
}

vault_post() {
    curl -sf -X POST "${VAULT_ADDR}/v1/${1}" \
        -H "X-Vault-Token: ${VAULT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$2"
}

vault_put() {
    curl -sf -X PUT "${VAULT_ADDR}/v1/${1}" \
        -H "X-Vault-Token: ${VAULT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$2"
}

# ── Wait for Vault to be reachable ────────────────────────────────────────────
echo -n "   Waiting for Vault to be reachable..."
for i in $(seq 1 30); do
    # Don't use -f flag; Vault returns 503 when uninitialized (which is normal)
    # We just need the endpoint to be responding (any 2xx, 4xx, 5xx)
    if curl -s "${VAULT_ADDR}/v1/sys/health?sealedok=true" >/dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 2
    if [ "$i" -eq 30 ]; then
        echo -e " ${RED}✗${NC}"
        echo -e "${RED}ERROR: Vault did not start within 60s${NC}"
        exit 1
    fi
done

# ── Read current Vault state ──────────────────────────────────────────────────
HEALTH=$(curl -sf "${VAULT_ADDR}/v1/sys/health?sealedok=true" 2>/dev/null || echo '{}')
INITIALIZED=$(parse_json_field "$HEALTH" "initialized")
SEALED=$(parse_json_field "$HEALTH" "sealed")

echo -e "   Initialized: ${INITIALIZED}  |  Sealed: ${SEALED}"
echo ""

# ── Case 3: Already running and unsealed ─────────────────────────────────────
if [ "$INITIALIZED" = "true" ] && [ "$SEALED" = "false" ]; then
    echo -e "${GREEN}✓${NC} Vault is already initialized and unsealed — nothing to do"
    if [ -f "$VAULT_KEYS_FILE" ]; then
        source "$VAULT_KEYS_FILE"
    fi
    echo ""
    echo "📋 Vault Access:"
    echo "   UI:    $VAULT_ADDR/ui"
    echo "   Token: ${VAULT_TOKEN}"
    exit 0
fi

# ── Case 2: Initialized but sealed (restart after stop) ──────────────────────
if [ "$INITIALIZED" = "true" ] && [ "$SEALED" = "true" ]; then
    echo "🔓 Vault is sealed — unsealing with saved keys..."

    if [ ! -f "$VAULT_KEYS_FILE" ]; then
        echo -e "${RED}ERROR: .vault-keys not found.${NC}"
        echo "   Vault is initialized but the unseal keys are missing."
        echo "   If you have the keys, create $VAULT_KEYS_FILE with:"
        echo "     VAULT_UNSEAL_KEY=<key>"
        echo "     VAULT_TOKEN=<root-token>"
        exit 1
    fi

    source "$VAULT_KEYS_FILE"

    if curl -sf -X PUT "${VAULT_ADDR}/v1/sys/unseal" \
        -H "Content-Type: application/json" \
        -d "{\"key\": \"${VAULT_UNSEAL_KEY}\"}" >/dev/null; then
        echo -e "${GREEN}✓${NC} Vault unsealed — all previous data restored"
    else
        echo -e "${RED}✗${NC} Unseal failed — check $VAULT_KEYS_FILE"
        exit 1
    fi

    echo ""
    echo "📋 Vault Access:"
    echo "   UI:    $VAULT_ADDR/ui"
    echo "   Token: ${VAULT_TOKEN}"
    exit 0
fi

# ── Case 1: Not initialized — fresh start ─────────────────────────────────────
echo "🆕 Vault is not initialized — running first-time setup..."
echo ""

# Initialize with a single unseal key (sufficient for local dev)
echo "   Initializing Vault..."
INIT_JSON=$(curl -sf -X PUT "${VAULT_ADDR}/v1/sys/init" \
    -H "Content-Type: application/json" \
    -d '{"secret_shares": 1, "secret_threshold": 1}')

# Extract the first unseal key (keys_base64 is an array, we need just the first element)
if command -v jq &>/dev/null; then
    UNSEAL_KEY=$(echo "$INIT_JSON" | jq -r '.keys_base64[0]')
    ROOT_TOKEN=$(echo "$INIT_JSON" | jq -r '.root_token')
else
    # Fallback: grep for the first quoted string after keys_base64:[
    UNSEAL_KEY=$(echo "$INIT_JSON" | grep -o '"keys_base64":\s*\["\([^"]*\)"' | sed 's/.*"\([^"]*\)".*/\1/')
    ROOT_TOKEN=$(echo "$INIT_JSON" | grep -o '"root_token":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$UNSEAL_KEY" ] || [ -z "$ROOT_TOKEN" ]; then
    echo -e "${RED}ERROR: Failed to parse init response${NC}"
    echo "Response: $INIT_JSON"
    exit 1
fi

# Save keys (gitignored)
cat > "$VAULT_KEYS_FILE" <<EOF
# Vault unseal keys — DO NOT COMMIT
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Delete this file + run reset-all.sh to start fully fresh
VAULT_UNSEAL_KEY=${UNSEAL_KEY}
VAULT_TOKEN=${ROOT_TOKEN}
EOF
chmod 600 "$VAULT_KEYS_FILE"
echo -e "${GREEN}✓${NC} Keys saved to .vault-keys"

# Unseal
curl -sf -X PUT "${VAULT_ADDR}/v1/sys/unseal" \
    -H "Content-Type: application/json" \
    -d "{\"key\": \"${UNSEAL_KEY}\"}" >/dev/null
echo -e "${GREEN}✓${NC} Vault unsealed"

export VAULT_TOKEN="$ROOT_TOKEN"

# Create a well-known dev token matching .env VAULT_TOKEN so existing scripts work
DEV_TOKEN_ID="${VAULT_DEV_ROOT_TOKEN_ID:-dev-root-token}"
curl -sf -X POST "${VAULT_ADDR}/v1/auth/token/create" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"id\": \"${DEV_TOKEN_ID}\", \"policies\": [\"root\"], \"no_default_policy\": true, \"ttl\": \"87600h\", \"renewable\": true}" \
    >/dev/null 2>&1 || true
echo -e "${GREEN}✓${NC} Dev token '${DEV_TOKEN_ID}' created"
echo ""

# ── Provision: mounts, policies, and seed secrets ─────────────────────────────
echo "📦 Provisioning secrets engines..."

vault_post "sys/mounts/secret" \
    '{"type": "kv", "options": {"version": "2"}}' >/dev/null 2>&1 || true
echo -e "   ${GREEN}✓${NC} KV v2 at secret/"

vault_post "sys/mounts/local/infrastructure" \
    '{"type": "kv", "options": {"version": "2"}}' >/dev/null 2>&1 || true
echo -e "   ${GREEN}✓${NC} KV v2 at local/infrastructure/"

vault_post "sys/mounts/transit" \
    '{"type": "transit"}' >/dev/null 2>&1 || true
echo -e "   ${GREEN}✓${NC} Transit at transit/"

echo ""
echo "📝 Applying policies..."
POLICY_FILE="$SERVICE_DIR/policies/dev-policy.hcl"
if [ -f "$POLICY_FILE" ]; then
    POLICY_CONTENT=$(cat "$POLICY_FILE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || \
                     cat "$POLICY_FILE" | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')
    vault_put "sys/policies/acl/dev-policy" \
        "{\"policy\": $(cat "$POLICY_FILE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')}" \
        >/dev/null 2>&1 || true
    echo -e "   ${GREEN}✓${NC} dev-policy"
fi

echo ""
echo "🔑 Seeding initial secrets..."

# Load env for registry/github values
if [ -f "$ROOT_DIR/.env" ]; then
    export $(grep -v '^#' "$ROOT_DIR/.env" | xargs 2>/dev/null)
fi

vault_post "secret/data/dev/ci" \
    "{\"data\": {
        \"registry_url\": \"${REGISTRY_URL:-http://localhost:${REGISTRY_PORT:-5002}}\",
        \"registry_user\": \"${REGISTRY_USERNAME:-}\",
        \"api_key\": \"dev-api-key-sample\"
    }}" >/dev/null 2>&1 || true
echo -e "   ${GREEN}✓${NC} secret/data/dev/ci"

vault_post "local/infrastructure/data/github" \
    "{\"data\": {
        \"GITHUB_USERNAME\": \"${GITHUB_USERNAME:-}\",
        \"GITHUB_TOKEN\": \"${GITHUB_TOKEN:-}\"
    }}" >/dev/null 2>&1 || true
echo -e "   ${GREEN}✓${NC} local/infrastructure/data/github"

echo ""
echo -e "${GREEN}✓${NC} Vault initialized and provisioned!"
echo ""
echo "📋 Vault Access:"
echo "   UI:    $VAULT_ADDR/ui"
echo "   Token: ${DEV_TOKEN_ID}  (matches .env VAULT_TOKEN)"
echo ""
echo "🔑 Unseal keys saved to: .vault-keys  (gitignored — keep safe)"
