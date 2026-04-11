#!/bin/bash
# PostgreSQL Backup Script
# Creates a backup of the PostgreSQL data volume

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$ROOT_DIR/backups/postgres"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "📦 Backing up PostgreSQL data..."

if docker run --rm -v postgres-data:/data -v "$BACKUP_DIR":/backup alpine tar czf "/backup/postgres-data-${TIMESTAMP}.tar.gz" -C /data . 2>/dev/null; then
    echo "✓ Backup created: $BACKUP_DIR/postgres-data-${TIMESTAMP}.tar.gz"
    
    # Clean up old backups (keep last 5)
    ls -t "$BACKUP_DIR"/postgres-data-*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
    echo "✓ Old backups cleaned (keeping last 5)"
else
    echo "✗ Backup failed"
    exit 1
fi
