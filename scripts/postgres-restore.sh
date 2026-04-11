#!/bin/bash
# PostgreSQL Restore Script
# Restores PostgreSQL data from a backup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$ROOT_DIR/backups/postgres"

show_help() {
    echo "Restore PostgreSQL Data from Backup"
    echo ""
    echo "Usage: ./scripts/postgres-restore.sh [backup-file]"
    echo ""
    echo "Arguments:"
    echo "  backup-file    Path to backup file (optional, lists available if not provided)"
    echo ""
    echo "Examples:"
    echo "  ./scripts/postgres-restore.sh                    # List available backups"
    echo "  ./scripts/postgres-restore.sh postgres-data-20240101_120000.tar.gz"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo "✗ Backup directory not found: $BACKUP_DIR"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Available backups:"
    ls -lh "$BACKUP_DIR"/postgres-data-*.tar.gz 2>/dev/null | awk '{print $9, $5}' || echo "  No backups found"
    exit 0
fi

BACKUP_FILE="$1"
if [ ! -f "$BACKUP_FILE" ]; then
    BACKUP_FILE="$BACKUP_DIR/$1"
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "✗ Backup file not found: $1"
    exit 1
fi

echo "⚠️  WARNING: This will replace existing PostgreSQL data!"
echo ""
read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted"
    exit 0
fi

echo "📦 Restoring PostgreSQL data from $BACKUP_FILE..."

# Stop postgres container if running
docker stop postgres 2>/dev/null || true

# Restore data
if docker run --rm -v postgres-data:/data -v "$BACKUP_FILE":/backup alpine sh -c "rm -rf /data/* && tar xzf /backup -C /data" 2>/dev/null; then
    echo "✓ Data restored successfully"
    echo "  Start PostgreSQL: docker-compose up -d postgres"
else
    echo "✗ Restore failed"
    exit 1
fi
