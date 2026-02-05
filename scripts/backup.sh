#!/bin/bash
# FRIDAY Database Backup Script
# Supports local backups and S3 upload

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups}"
DATA_DIR="${DATA_DIR:-/data}"
DB_FILE="${DATA_DIR}/leaderboard.db"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# S3 Configuration
S3_BUCKET="${S3_BUCKET_NAME:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting FRIDAY backup..."

# Check if database exists
if [ ! -f "$DB_FILE" ]; then
    echo "[$(date)] ERROR: Database file not found at $DB_FILE"
    exit 1
fi

# Create SQLite backup (uses atomic copy)
echo "[$(date)] Creating database backup..."
BACKUP_FILE="$BACKUP_DIR/leaderboard_$DATE.db"

if command -v sqlite3 &> /dev/null; then
    sqlite3 "$DB_FILE" ".backup '$BACKUP_FILE'"
else
    cp "$DB_FILE" "$BACKUP_FILE"
fi

# Compress backup
echo "[$(date)] Compressing backup..."
gzip -f "$BACKUP_FILE"
BACKUP_FILE="$BACKUP_FILE.gz"

# Calculate checksum
echo "[$(date)] Calculating checksum..."
cd "$BACKUP_DIR"
sha256sum "$(basename $BACKUP_FILE)" > "leaderboard_$DATE.sha256"

# Upload to S3 if configured
if [ -n "$S3_BUCKET" ] && [ -n "$AWS_ACCESS_KEY_ID" ]; then
    echo "[$(date)] Uploading to S3..."
    
    # Set AWS region
    export AWS_REGION
    
    # Upload backup
    aws s3 cp "$BACKUP_FILE" "s3://$S3_BUCKET/backups/" --storage-class STANDARD_IA
    
    # Upload checksum
    aws s3 cp "leaderboard_$DATE.sha256" "s3://$S3_BUCKET/backups/"
    
    echo "[$(date)] S3 upload complete"
    
    # Clean old S3 backups (keep last 30 days)
    echo "[$(date)] Cleaning old S3 backups..."
    aws s3 ls "s3://$S3_BUCKET/backups/" | grep "leaderboard_" | awk '{print $4}' | sort -r | tail -n +31 | while read -r file; do
        aws s3 rm "s3://$S3_BUCKET/backups/$file"
        echo "[$(date)] Deleted from S3: $file"
    done
fi

# Clean local backups older than retention period
echo "[$(date)] Cleaning old local backups..."
find "$BACKUP_DIR" -name "leaderboard_*.db.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "leaderboard_*.sha256" -mtime +$RETENTION_DAYS -delete

# Log backup info
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "[$(date)] Backup complete: $(basename $BACKUP_FILE) ($BACKUP_SIZE)"

# Optional: Send notification
if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    curl -s -H "Content-Type: application/json" \
        -d "{\"content\":\"✅ FRIDAY backup completed: $(basename $BACKUP_FILE) ($BACKUP_SIZE)\"}" \
        "$DISCORD_WEBHOOK_URL" > /dev/null
fi

if [ -n "$SLACK_WEBHOOK_URL" ]; then
    curl -s -H "Content-Type: application/json" \
        -d "{\"text\":\"✅ FRIDAY backup completed: $(basename $BACKUP_FILE) ($BACKUP_SIZE)\"}" \
        "$SLACK_WEBHOOK_URL" > /dev/null
fi

echo "[$(date)] Backup process finished successfully"
