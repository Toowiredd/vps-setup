#!/bin/bash

# Configuration
WORKSPACE_DIR="/opt/storage-migration"
SNAPSHOT_DIR="${WORKSPACE_DIR}/snapshots"
LOG_FILE="${WORKSPACE_DIR}/logs/snapshot_verification.log"
STORAGE_BUCKET="serversnaps"
TEMP_DIR="/tmp/snapshot-verify"
VERIFICATION_REPORT="${WORKSPACE_DIR}/reports/snapshot_verification_$(date +%Y%m%d).html"

# Create required directories
mkdir -p "${SNAPSHOT_DIR}" "$(dirname "${LOG_FILE}")" "${TEMP_DIR}" "$(dirname "${VERIFICATION_REPORT}")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Function to check required components
check_requirements() {
    local missing_deps=()

    # Check for required commands
    for cmd in s3cmd tar sha256sum jq curl; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_message "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# Function to verify local snapshot integrity
verify_local_snapshot() {
    local snapshot_dir="$1"
    local result=0

    log_message "INFO" "Verifying local snapshot: ${snapshot_dir}"

    # Check if snapshot directory exists
    if [ ! -d "${snapshot_dir}" ]; then
        log_message "ERROR" "Snapshot directory not found: ${snapshot_dir}"
        return 1
    fi

    # Verify required components
    local required_dirs=("config" "data" "logs" "system")
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "${snapshot_dir}/${dir}" ]; then
            log_message "ERROR" "Missing required directory: ${dir}"
            result=1
        else
            # Verify contents of each directory
            case "${dir}" in
                "config")
                    for file in nginx.tar.gz systemd.tar.gz ssl.tar.gz; do
                        if [ ! -f "${snapshot_dir}/${dir}/${file}" ]; then
                            log_message "ERROR" "Missing config file: ${file}"
                            result=1
                        else
                            if ! tar tzf "${snapshot_dir}/${dir}/${file}" &> /dev/null; then
                                log_message "ERROR" "Invalid archive: ${file}"
                                result=1
                            fi
                        fi
                    done
                    ;;
                "data")
                    for file in dashboard.tar.gz scripts.tar.gz metrics.tar.gz; do
                        if [ ! -f "${snapshot_dir}/${dir}/${file}" ]; then
                            log_message "ERROR" "Missing data file: ${file}"
                            result=1
                        else
                            if ! tar tzf "${snapshot_dir}/${dir}/${file}" &> /dev/null; then
                                log_message "ERROR" "Invalid archive: ${file}"
                                result=1
                            fi
                        fi
                    done
                    ;;
                "logs")
                    if [ ! -f "${snapshot_dir}/${dir}/all_logs.tar.gz" ]; then
                        log_message "ERROR" "Missing logs archive"
                        result=1
                    else
                        if ! tar tzf "${snapshot_dir}/${dir}/all_logs.tar.gz" &> /dev/null; then
                            log_message "ERROR" "Invalid logs archive"
                            result=1
                        fi
                    fi
                    ;;
                "system")
                    if [ ! -f "${snapshot_dir}/${dir}/state.txt" ]; then
                        log_message "ERROR" "Missing system state file"
                        result=1
                    fi
                    ;;
            esac
        fi
    done

    # Verify metadata
    if [ ! -f "${snapshot_dir}/metadata.json" ]; then
        log_message "ERROR" "Missing metadata.json"
        result=1
    else
        if ! jq . "${snapshot_dir}/metadata.json" &> /dev/null; then
            log_message "ERROR" "Invalid metadata JSON format"
            result=1
        else
            log_message "INFO" "Metadata format verified"

            # Verify metadata content
            local required_fields=("snapshot_name" "timestamp" "system" "components" "files")
            for field in "${required_fields[@]}"; do
                if ! jq -e ".${field}" "${snapshot_dir}/metadata.json" &> /dev/null; then
                    log_message "ERROR" "Missing required metadata field: ${field}"
                    result=1
                fi
            done
        fi
    fi

    return $result
}

# Function to verify remote snapshot
verify_remote_snapshot() {
    local snapshot_name="$1"
    local result=0

    log_message "INFO" "Verifying remote snapshot: ${snapshot_name}"

    # Create temporary directory for remote snapshot
    local temp_dir="${TEMP_DIR}/remote_${snapshot_name}"
    mkdir -p "${temp_dir}"

    # Download snapshot and checksum
    if ! s3cmd get "s3://${STORAGE_BUCKET}/snapshots/${snapshot_name}" "${temp_dir}/" &> /dev/null; then
        log_message "ERROR" "Failed to download remote snapshot"
        rm -rf "${temp_dir}"
        return 1
    fi

    if ! s3cmd get "s3://${STORAGE_BUCKET}/snapshots/${snapshot_name%.tar.gz}.sha256" "${temp_dir}/" &> /dev/null; then
        log_message "WARNING" "Remote checksum file not found"
        result=1
    fi

    # Verify downloaded snapshot
    verify_local_snapshot "${temp_dir}/${snapshot_name}"
    result=$?

    # Cleanup
    rm -rf "${temp_dir}"

    return $result
}

# Function to generate HTML report
generate_report() {
    local total_snapshots=$1
    local verified_snapshots=$2
    local failed_snapshots=$3

    cat > "${VERIFICATION_REPORT}" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Snapshot Verification Report - $(date '+%Y-%m-%d')</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f8f9fa; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .success { color: green; }
        .warning { color: orange; }
        .error { color: red; }
        .details { margin-top: 20px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border: 1px solid #ddd; }
        th { background: #f8f9fa; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Snapshot Verification Report</h1>
        <p>Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>
    </div>

    <div class="summary">
        <h2>Summary</h2>
        <p>Total Snapshots: ${total_snapshots}</p>
        <p class="success">Successfully Verified: ${verified_snapshots}</p>
        <p class="error">Failed Verification: ${failed_snapshots}</p>
    </div>

    <div class="details">
        <h2>Verification Log</h2>
        <pre>$(tail -n 50 "${LOG_FILE}")</pre>
    </div>
</body>
</html>
EOF
}

# Main verification process
main() {
    local total_snapshots=0
    local verified_snapshots=0
    local failed_snapshots=0

    # Check requirements
    check_requirements

    log_message "INFO" "Starting snapshot verification"

    # Verify local snapshots
    log_message "INFO" "Verifying local snapshots..."
    while IFS= read -r snapshot_dir; do
        if [ -d "${snapshot_dir}" ]; then
            ((total_snapshots++))
            if verify_local_snapshot "${snapshot_dir}"; then
                ((verified_snapshots++))
                echo -e "${GREEN}✓ Verified: $(basename "${snapshot_dir}")${NC}"
            else
                ((failed_snapshots++))
                echo -e "${RED}✗ Failed: $(basename "${snapshot_dir}")${NC}"
            fi
        fi
    done < <(find "${SNAPSHOT_DIR}" -mindepth 1 -maxdepth 1 -type d)

    # Verify remote snapshots
    log_message "INFO" "Verifying remote snapshots..."
    while IFS= read -r snapshot; do
        snapshot=$(basename "${snapshot}")
        if [ -n "${snapshot}" ]; then
            ((total_snapshots++))
            if verify_remote_snapshot "${snapshot}"; then
                ((verified_snapshots++))
                echo -e "${GREEN}✓ Verified remote: ${snapshot}${NC}"
            else
                ((failed_snapshots++))
                echo -e "${RED}✗ Failed remote: ${snapshot}${NC}"
            fi
        fi
    done < <(s3cmd ls "s3://${STORAGE_BUCKET}/snapshots/" | awk '{print $4}')

    # Generate report
    log_message "INFO" "Generating verification report"
    generate_report "${total_snapshots}" "${verified_snapshots}" "${failed_snapshots}"

    # Final summary
    echo
    echo "Verification Summary:"
    echo "===================="
    echo "Total snapshots: ${total_snapshots}"
    echo -e "${GREEN}Successfully verified: ${verified_snapshots}${NC}"
    echo -e "${RED}Failed verification: ${failed_snapshots}${NC}"
    echo
    echo "Report generated: ${VERIFICATION_REPORT}"

    # Set exit code based on verification results
    [ ${failed_snapshots} -eq 0 ]
}

# Run main function
main "$@"