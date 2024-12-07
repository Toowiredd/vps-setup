#!/bin/bash

# Configuration
SOURCE_BUCKET="tysbucket"
LOG_FILE="/tmp/storage_cleanup.log"

# Initialize log
echo "Starting cleanup at $(date)" | tee "$LOG_FILE"

# Function to delete files
delete_files() {
    local bucket="$1"
    local pattern="$2"

    echo "Looking for files matching pattern: $pattern" | tee -a "$LOG_FILE"

    # List and delete matching files
    s3cmd ls --recursive "s3://$bucket/" | while read -r line; do
        if echo "$line" | grep -q "$pattern"; then
            # Extract file path
            filepath=$(echo "$line" | awk '{print $4}')
            if [ -n "$filepath" ]; then
                echo "Found file to delete: $filepath" | tee -a "$LOG_FILE"
                s3cmd del "$filepath" 2>&1 | tee -a "$LOG_FILE"
            fi
        fi
    done
}

# Show current contents
echo "Current bucket contents:" | tee -a "$LOG_FILE"
s3cmd ls --recursive "s3://$SOURCE_BUCKET/" 2>&1 | tee -a "$LOG_FILE"

# Delete node_modules files
echo -e "\nDeleting node_modules files..." | tee -a "$LOG_FILE"
delete_files "$SOURCE_BUCKET" "node_modules"

# Verify cleanup
echo -e "\nVerifying remaining contents:" | tee -a "$LOG_FILE"
s3cmd ls --recursive "s3://$SOURCE_BUCKET/" 2>&1 | tee -a "$LOG_FILE"

echo "Cleanup completed at $(date)" | tee -a "$LOG_FILE"
echo "Check $LOG_FILE for full details."