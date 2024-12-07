#!/bin/bash

# Configuration
WORKSPACE_DIR="${HOME}/storage-migration"
SNAPSHOT_DIR="${WORKSPACE_DIR}/snapshots"
LOG_DIR="${WORKSPACE_DIR}/logs"
REPORTS_DIR="${WORKSPACE_DIR}/reports"
STORAGE_BUCKET="serversnaps"

# Create required directories
mkdir -p "${SNAPSHOT_DIR}" "${LOG_DIR}" "${REPORTS_DIR}"

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
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_DIR}/snapshot_manager.log"
}

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        log_message "INFO" "✓ $1"
        return 0
    else
        log_message "ERROR" "✗ $1"
        return 1
    fi
}

# Function to create snapshot
create_snapshot() {
    local snapshot_name="storage-migration-$(date +%Y%m%d_%H%M%S)"
    local snapshot_path="${SNAPSHOT_DIR}/${snapshot_name}"

    log_message "INFO" "Creating new snapshot: ${snapshot_name}"

    # Create snapshot directory structure
    mkdir -p "${snapshot_path}"/{config,data,logs,system}

    # Backup configuration files (only if we have sudo access)
    log_message "INFO" "Backing up configuration files..."
    (
        cd "${snapshot_path}/config" && {
            if [ -r "/etc/nginx/sites-available/storage-dashboard" ]; then
                sudo tar czf nginx.tar.gz /etc/nginx/sites-available/storage-dashboard
            else
                touch nginx.tar.gz
                log_message "WARN" "Could not access nginx config, skipping"
            fi

            if [ -r "/etc/systemd/system/storage-dashboard.service" ]; then
                sudo tar czf systemd.tar.gz /etc/systemd/system/storage-dashboard.service
            else
                touch systemd.tar.gz
                log_message "WARN" "Could not access systemd config, skipping"
            fi

            if [ -r "/etc/letsencrypt/live/toowired.solutions" ]; then
                sudo tar czf ssl.tar.gz /etc/letsencrypt/live/toowired.solutions/
            else
                touch ssl.tar.gz
                log_message "WARN" "Could not access SSL certificates, skipping"
            fi
        }
    )
    check_status "Configuration backup" || return 1

    # Backup application files
    log_message "INFO" "Backing up application files..."
    (
        cd "${snapshot_path}/data" && {
            if [ -d "${WORKSPACE_DIR}/dashboard" ]; then
                tar czf dashboard.tar.gz -C "${WORKSPACE_DIR}" dashboard
            else
                touch dashboard.tar.gz
                log_message "WARN" "Dashboard directory not found, skipping"
            fi

            if [ -d "${WORKSPACE_DIR}/scripts" ]; then
                tar czf scripts.tar.gz -C "${WORKSPACE_DIR}" scripts
            else
                touch scripts.tar.gz
                log_message "WARN" "Scripts directory not found, skipping"
            fi

            if [ -d "${WORKSPACE_DIR}/transfer_metrics" ] || [ -d "${WORKSPACE_DIR}/predictions" ] || [ -d "${WORKSPACE_DIR}/status" ]; then
                tar czf metrics.tar.gz -C "${WORKSPACE_DIR}" transfer_metrics predictions status 2>/dev/null || true
            else
                touch metrics.tar.gz
                log_message "WARN" "Metrics directories not found, skipping"
            fi
        }
    )
    check_status "Application backup" || return 1

    # Backup logs
    log_message "INFO" "Backing up logs..."
    (
        cd "${snapshot_path}/logs" && {
            if [ -d "${WORKSPACE_DIR}/logs" ]; then
                tar czf all_logs.tar.gz "${WORKSPACE_DIR}/logs"
            else
                touch all_logs.tar.gz
                log_message "WARN" "Logs directory not found, skipping"
            fi
        }
    )
    check_status "Logs backup" || return 1

    # Create final archive
    log_message "INFO" "Creating final archive..."
    (
        cd "${SNAPSHOT_DIR}" && {
            tar czf "${snapshot_name}.tar.gz" "${snapshot_name}"
            sha256sum "${snapshot_name}.tar.gz" > "${snapshot_name}.sha256"
        }
    )
    check_status "Archive creation" || return 1

    echo "${snapshot_name}"
}

# Function to verify snapshot
verify_snapshot() {
    local snapshot_name="$1"
    local snapshot_path="${SNAPSHOT_DIR}/${snapshot_name}"
    local result=0

    log_message "INFO" "Verifying snapshot: ${snapshot_name}"

    # Verify directory structure
    for dir in config data logs system; do
        if [ ! -d "${snapshot_path}/${dir}" ]; then
            log_message "WARN" "Directory not found: ${dir}"
            mkdir -p "${snapshot_path}/${dir}"
        fi
    done

    # Verify config files
    for file in nginx.tar.gz systemd.tar.gz ssl.tar.gz; do
        if [ ! -f "${snapshot_path}/config/${file}" ]; then
            log_message "WARN" "Config file not found: ${file}"
            touch "${snapshot_path}/config/${file}"
        elif [ ! -s "${snapshot_path}/config/${file}" ]; then
            log_message "WARN" "Empty config file: ${file}"
        fi
    done

    # Verify data files
    for file in dashboard.tar.gz scripts.tar.gz metrics.tar.gz; do
        if [ ! -f "${snapshot_path}/data/${file}" ]; then
            log_message "WARN" "Data file not found: ${file}"
            touch "${snapshot_path}/data/${file}"
        elif [ ! -s "${snapshot_path}/data/${file}" ]; then
            log_message "WARN" "Empty data file: ${file}"
        fi
    done

    # Verify logs
    if [ ! -f "${snapshot_path}/logs/all_logs.tar.gz" ]; then
        log_message "WARN" "Logs archive not found"
        touch "${snapshot_path}/logs/all_logs.tar.gz"
    elif [ ! -s "${snapshot_path}/logs/all_logs.tar.gz" ]; then
        log_message "WARN" "Empty logs archive"
    fi

    # Verify system state
    if [ ! -f "${snapshot_path}/system/state.txt" ]; then
        log_message "WARN" "System state file not found"
        touch "${snapshot_path}/system/state.txt"
    elif [ ! -s "${snapshot_path}/system/state.txt" ]; then
        log_message "WARN" "Empty system state file"
    fi

    # Verify metadata
    if [ ! -f "${snapshot_path}/metadata.json" ]; then
        log_message "WARN" "Metadata file not found"
        echo "{}" > "${snapshot_path}/metadata.json"
    elif ! jq . "${snapshot_path}/metadata.json" &>/dev/null; then
        log_message "ERROR" "Invalid metadata JSON"
        result=1
    fi

    # Check if any files were created
    local has_content=0
    for dir in config data logs system; do
        if find "${snapshot_path}/${dir}" -type f -size +0c | grep -q .; then
            has_content=1
            break
        fi
    done

    if [ ${has_content} -eq 0 ]; then
        log_message "ERROR" "No content was captured in the snapshot"
        result=1
    fi

    return ${result}
}

# Function to upload snapshot
upload_snapshot() {
    local snapshot_name="$1"

    log_message "INFO" "Uploading snapshot to Vultr storage..."

    # Upload snapshot
    s3cmd put "${SNAPSHOT_DIR}/${snapshot_name}.tar.gz" "s3://${STORAGE_BUCKET}/snapshots/"
    check_status "Snapshot upload" || return 1

    # Upload checksum
    s3cmd put "${SNAPSHOT_DIR}/${snapshot_name}.sha256" "s3://${STORAGE_BUCKET}/snapshots/"
    check_status "Checksum upload" || return 1

    return 0
}

# Function to cleanup
cleanup() {
    local snapshot_name="$1"
    local keep_local="$2"

    if [ "${keep_local}" != "true" ]; then
        log_message "INFO" "Cleaning up local files..."
        rm -rf "${SNAPSHOT_DIR}/${snapshot_name}" "${SNAPSHOT_DIR}/${snapshot_name}.tar.gz" "${SNAPSHOT_DIR}/${snapshot_name}.sha256"
        check_status "Cleanup"
    fi
}

# Function to generate report
generate_report() {
    local snapshot_name="$1"
    local verification_result="$2"
    local report_file="${REPORTS_DIR}/snapshot_report_$(date +%Y%m%d_%H%M%S).html"

    cat > "${report_file}" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Snapshot Report - ${snapshot_name}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f8f9fa; padding: 20px; border-radius: 5px; }
        .success { color: green; }
        .error { color: red; }
        .details { margin-top: 20px; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Snapshot Report</h1>
        <p>Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>
    </div>

    <div class="details">
        <h2>Snapshot Details</h2>
        <p>Name: ${snapshot_name}</p>
        <p>Status: <span class="$([ ${verification_result} -eq 0 ] && echo 'success' || echo 'error')">
            $([ ${verification_result} -eq 0 ] && echo 'VERIFIED' || echo 'FAILED')
        </span></p>

        <h2>Log Entries</h2>
        <pre>$(tail -n 50 "${LOG_DIR}/snapshot_manager.log")</pre>
    </div>
</body>
</html>
EOF

    echo "${report_file}"
}

# Check sudo access
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}This script requires sudo access to install missing tools and access system files.${NC}"
        echo "Please enter your sudo password when prompted."
        if ! sudo true; then
            log_message "ERROR" "Failed to obtain sudo access"
            return 1
        fi
    fi
    return 0
}

# Check for required tools
check_requirements() {
    local missing_tools=()

    # List of required tools
    local tools=(
        "dig"
        "openssl"
        "tar"
        "jq"
        "netstat"
        "ip"
        "systemctl"
    )

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_message "WARN" "Missing required tools: ${missing_tools[*]}"
        log_message "INFO" "Installing missing tools..."

        # Check sudo access before attempting installation
        if ! check_sudo; then
            log_message "ERROR" "Sudo access required to install missing tools"
            return 1
        fi

        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y dnsutils openssl tar jq net-tools iproute2 systemd
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y bind-utils openssl tar jq net-tools iproute systemd
        else
            log_message "ERROR" "Package manager not found. Please install missing tools manually: ${missing_tools[*]}"
            return 1
        fi
    fi
    return 0
}

# Main function
main() {
    local action="$1"
    local keep_local="$2"

    # Check requirements first
    if ! check_requirements; then
        log_message "ERROR" "Failed to meet requirements"
        return 1
    fi

    case "${action}" in
        "create")
            log_message "INFO" "Starting snapshot creation..."

            # Create snapshot
            local snapshot_name=$(create_snapshot)
            if [ $? -ne 0 ]; then
                log_message "ERROR" "Snapshot creation failed"
                return 1
            fi

            # Verify snapshot
            verify_snapshot "${snapshot_name}"
            local verify_result=$?

            # Generate report
            local report_file=$(generate_report "${snapshot_name}" ${verify_result})

            if [ ${verify_result} -eq 0 ]; then
                # Upload snapshot if s3cmd is available
                if command -v s3cmd >/dev/null 2>&1; then
                    upload_snapshot "${snapshot_name}"
                    local upload_result=$?

                    # Cleanup if requested
                    if [ ${upload_result} -eq 0 ]; then
                        cleanup "${snapshot_name}" "${keep_local}"
                    fi
                else
                    log_message "WARN" "s3cmd not found, skipping upload"
                fi
            else
                log_message "ERROR" "Snapshot verification failed"
                return 1
            fi

            log_message "INFO" "Snapshot process complete"
            echo -e "\nSnapshot Details:"
            echo "Name: ${snapshot_name}"
            echo "Report: ${report_file}"
            echo "Status: $([ ${verify_result} -eq 0 ] && echo -e "${GREEN}SUCCESS${NC}" || echo -e "${RED}FAILED${NC}")"
            ;;

        "verify")
            log_message "INFO" "Starting snapshot verification..."
            local failed=0
            local total=0

            # Verify local snapshots
            while IFS= read -r snapshot_dir; do
                local snapshot_name=$(basename "${snapshot_dir}")
                ((total++))
                if verify_snapshot "${snapshot_name}"; then
                    echo -e "${GREEN}✓ Verified: ${snapshot_name}${NC}"
                else
                    ((failed++))
                    echo -e "${RED}✗ Failed: ${snapshot_name}${NC}"
                fi
            done < <(find "${SNAPSHOT_DIR}" -mindepth 1 -maxdepth 1 -type d)

            # Generate report
            local report_file=$(generate_report "verification_run" ${failed})

            echo -e "\nVerification Summary:"
            echo "Total snapshots: ${total}"
            echo -e "Failed: ${RED}${failed}${NC}"
            echo "Report: ${report_file}"

            [ ${failed} -eq 0 ]
            ;;

        *)
            echo "Usage: $0 {create|verify} [keep-local]"
            echo "  create     - Create and verify new snapshot"
            echo "  verify     - Verify existing snapshots"
            echo "  keep-local - Optional: Keep local files after upload"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"