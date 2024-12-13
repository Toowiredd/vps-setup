#!/bin/bash

# Check if timestamp argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <snapshot_timestamp>"
    echo "Example: $0 20240115_123456"
    exit 1
fi

TIMESTAMP="$1"
WORKSPACE_DIR="/opt/storage-migration"
SNAPSHOT_DIR="${WORKSPACE_DIR}/snapshots"
SNAPSHOT_PATH="${SNAPSHOT_DIR}/${TIMESTAMP}"
BACKUP_SUFFIX=".pre_restore_$(date +%Y%m%d_%H%M%S)"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        log_message "✓ $1"
    else
        log_message "✗ ERROR: $1"
        exit 1
    fi
}

# Verify snapshot exists
if [ ! -d "${SNAPSHOT_PATH}" ]; then
    log_message "Error: Snapshot directory not found: ${SNAPSHOT_PATH}"
    exit 1
fi

# Verify metadata exists
if [ ! -f "${SNAPSHOT_PATH}/metadata.json" ]; then
    log_message "Error: Snapshot metadata not found"
    exit 1
fi

# Stop services
log_message "Stopping services..."
sudo systemctl stop storage-dashboard nginx
check_status "Services stopped"

# Create backup of current state
log_message "Creating backup of current state..."
sudo tar czf "${WORKSPACE_DIR}/pre_restore_backup.tar.gz" \
    /etc/nginx/sites-available/storage-dashboard \
    /etc/systemd/system/storage-dashboard.service \
    /etc/letsencrypt/live/toowired.solutions/ \
    "${WORKSPACE_DIR}"/{dashboard,scripts,transfer_metrics,predictions,status,logs}
check_status "Current state backup"

# Restore configuration files
log_message "Restoring configuration files..."
sudo tar xzf "${SNAPSHOT_PATH}/config/nginx.tar.gz" -C /
check_status "Nginx configuration restore"

sudo tar xzf "${SNAPSHOT_PATH}/config/systemd.tar.gz" -C /
check_status "Systemd configuration restore"

sudo tar xzf "${SNAPSHOT_PATH}/config/ssl.tar.gz" -C /
check_status "SSL certificates restore"

# Restore application files
log_message "Restoring application files..."
tar xzf "${SNAPSHOT_PATH}/data/dashboard.tar.gz" -C "${WORKSPACE_DIR}"
check_status "Dashboard restore"

tar xzf "${SNAPSHOT_PATH}/data/scripts.tar.gz" -C "${WORKSPACE_DIR}"
check_status "Scripts restore"

tar xzf "${SNAPSHOT_PATH}/data/metrics.tar.gz" -C "${WORKSPACE_DIR}"
check_status "Metrics restore"

# Restore logs
log_message "Restoring logs..."
sudo tar xzf "${SNAPSHOT_PATH}/logs/all_logs.tar.gz" -C "${WORKSPACE_DIR}"
check_status "Logs restore"

# Fix permissions
log_message "Fixing permissions..."
sudo chown -R $(whoami):$(whoami) "${WORKSPACE_DIR}"
sudo chmod -R 755 "${WORKSPACE_DIR}"
check_status "Permissions fixed"

# Reload systemd
log_message "Reloading systemd..."
sudo systemctl daemon-reload
check_status "Systemd reload"

# Start services
log_message "Starting services..."
sudo systemctl start nginx storage-dashboard
check_status "Services started"

# Verify services
log_message "Verifying services..."
systemctl is-active --quiet nginx
check_status "Nginx is running"

systemctl is-active --quiet storage-dashboard
check_status "Storage dashboard is running"

# Test endpoints
log_message "Testing endpoints..."
curl -sf https://toowired.solutions/dashboard > /dev/null
check_status "Dashboard endpoint test"

curl -sf https://toowired.solutions/dashboard/api/status > /dev/null
check_status "API endpoint test"

log_message "Restore complete!"
echo
echo "Restore Summary:"
echo "- Snapshot: ${TIMESTAMP}"
echo "- Pre-restore backup: ${WORKSPACE_DIR}/pre_restore_backup.tar.gz"
echo "- Services restarted and verified"
echo "- Endpoints tested and working"
echo
echo "To verify the system:"
echo "1. Check dashboard at https://toowired.solutions/dashboard"
echo "2. Verify all metrics and data are present"
echo "3. Test storage migration functionality"
echo
echo "If issues occur, you can roll back using:"
echo "tar xzf ${WORKSPACE_DIR}/pre_restore_backup.tar.gz -C /"