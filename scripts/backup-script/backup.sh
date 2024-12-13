#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backup_$TIMESTAMP"
BUCKET_NAME="toowired_bucket"
mkdir -p "$BACKUP_DIR"
cp -r /etc/ssh "$BACKUP_DIR/"
cp -r /etc/fail2ban "$BACKUP_DIR/"
cp /etc/fstab "$BACKUP_DIR/"
cp /etc/hostname "$BACKUP_DIR/"
cp /etc/hosts "$BACKUP_DIR/"
cd /tmp
tar czf "backup_$TIMESTAMP.tar.gz" "backup_$TIMESTAMP"
s3cmd put "backup_$TIMESTAMP.tar.gz" "s3://$BUCKET_NAME/system_backups/"
rm -rf "$BACKUP_DIR"
rm "backup_$TIMESTAMP.tar.gz"
