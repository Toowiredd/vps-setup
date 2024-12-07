#!/bin/bash

# Configuration
WORKSPACE_DIR="/opt/storage-migration"
SNAPSHOT_DIR="${WORKSPACE_DIR}/snapshots"
LOG_FILE="${WORKSPACE_DIR}/logs/snapshots.log"
RETENTION_DAYS=30
MAX_SNAPSHOTS=10
STORAGE_BUCKET="serversnaps"

# Create required directories
mkdir -p "${SNAPSHOT_DIR}" "$(dirname "${LOG_FILE}")"

# Function to log messages
log_message() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "${message}" | tee -a "${LOG_FILE}"
}

# Function to clean old snapshots
cleanup_old_snapshots() {
    log_message "Cleaning up old snapshots..."

    # Local cleanup
    find "${SNAPSHOT_DIR}" -name "storage-migration-*.tar.gz" -mtime +${RETENTION_DAYS} -delete
    find "${SNAPSHOT_DIR}" -name "storage-migration-*.sha256" -mtime +${RETENTION_DAYS} -delete

    # Remote cleanup
    local old_snapshots=$(s3cmd ls s3://${STORAGE_BUCKET}/snapshots/ | awk '{print $4}' | sort -r | tail -n +${MAX_SNAPSHOTS})
    if [ ! -z "${old_snapshots}" ]; then
        echo "${old_snapshots}" | while read snapshot; do
            s3cmd del "${snapshot}"
            log_message "Deleted old snapshot: ${snapshot}"
        done
    fi
}

# Function to check disk space
check_disk_space() {
    local available_space=$(df -m "${SNAPSHOT_DIR}" | awk 'NR==2 {print $4}')
    if [ "${available_space}" -lt 1024 ]; then  # Less than 1GB
        log_message "WARNING: Low disk space (${available_space}MB available)"
        cleanup_old_snapshots
    fi
}

# Create snapshot
create_snapshot() {
    log_message "Starting scheduled snapshot creation..."

    # Check disk space before starting
    check_disk_space

    # Run the snapshot creation script
    if "${WORKSPACE_DIR}/scripts/storage/create_vultr_snapshot.sh"; then
        log_message "Snapshot created successfully"

        # Upload to Vultr storage
        local snapshot_file=$(ls -t "${SNAPSHOT_DIR}"/*.tar.gz | head -1)
        local checksum_file="${snapshot_file%.tar.gz}.sha256"

        log_message "Uploading snapshot to Vultr storage..."
        s3cmd put "${snapshot_file}" "s3://${STORAGE_BUCKET}/snapshots/"
        s3cmd put "${checksum_file}" "s3://${STORAGE_BUCKET}/snapshots/"

        # Clean up old snapshots
        cleanup_old_snapshots
    else
        log_message "ERROR: Snapshot creation failed"
        return 1
    fi
}

# Setup cron job
setup_cron() {
    local cron_file="/etc/cron.d/storage-snapshots"

    # Create cron job for daily snapshots at 2 AM
    echo "0 2 * * * root ${WORKSPACE_DIR}/scripts/storage/scheduled_snapshots.sh run >> ${LOG_FILE} 2>&1" | sudo tee "${cron_file}"

    # Set proper permissions
    sudo chmod 644 "${cron_file}"

    log_message "Cron job installed at ${cron_file}"
}

# Main execution
case "$1" in
    "run")
        create_snapshot
        ;;
    "setup")
        setup_cron
        log_message "Scheduled snapshot system installed"
        ;;
    "cleanup")
        cleanup_old_snapshots
        log_message "Manual cleanup completed"
        ;;
    "status")
        echo "Snapshot System Status"
        echo "====================="
        echo "Latest snapshots:"
        ls -lh "${SNAPSHOT_DIR}"/*.tar.gz 2>/dev/null || echo "No local snapshots found"
        echo
        echo "Remote snapshots:"
        s3cmd ls s3://${STORAGE_BUCKET}/snapshots/
        echo
        echo "Disk space:"
        df -h "${SNAPSHOT_DIR}"
        echo
        echo "Last 5 log entries:"
        tail -n 5 "${LOG_FILE}"
        ;;
    *)
        echo "Usage: $0 {run|setup|cleanup|status}"
        echo "  run     - Create a new snapshot"
        echo "  setup   - Install cron job for daily snapshots"
        echo "  cleanup - Remove old snapshots"
        echo "  status  - Show snapshot system status"
        exit 1
        ;;
esac

exit 0