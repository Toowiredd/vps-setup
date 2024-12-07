#!/bin/bash

# Configuration
SOURCE_BUCKET="tysbucket"
TARGET_BUCKET="toowired_bucket"
LOG_FILE="/tmp/storage_migration.log"

# Initialize log
echo "Starting migration at $(date)" > "$LOG_FILE"

# Create directory structure
echo "Creating directory structure..." | tee -a "$LOG_FILE"
for dir in system_backups documents media archives; do
    echo "Creating $dir directory..." | tee -a "$LOG_FILE"
    touch empty.tmp
    s3cmd put empty.tmp "s3://$TARGET_BUCKET/$dir/" >> "$LOG_FILE" 2>&1
    rm empty.tmp
done

# Function to categorize files
categorize_file() {
    local file="$1"

    # Extract file extension
    ext="${file##*.}"
    ext="${ext,,}"  # Convert to lowercase

    # Media files
    if [[ "$ext" =~ ^(jpg|jpeg|png|gif|mp4|mov|avi|mp3|wav)$ ]]; then
        echo "media"
    # Documents
    elif [[ "$ext" =~ ^(pdf|doc|docx|txt|xls|xlsx|csv)$ ]]; then
        echo "documents"
    # System backups
    elif [[ "$file" =~ "backup" || "$file" =~ "system" ]]; then
        echo "system_backups"
    # Archives
    elif [[ "$ext" =~ ^(zip|tar|gz|rar|7z)$ ]]; then
        echo "archives"
    else
        echo "documents"  # Default category
    fi
}

# List all files in source bucket
echo "Listing files from source bucket..." | tee -a "$LOG_FILE"
s3cmd ls --recursive "s3://$SOURCE_BUCKET/" | while read -r line; do
    # Extract file path
    filepath=$(echo "$line" | awk '{$1=$2=$3=""; print substr($0,4)}' | sed 's/^[ \t]*//')

    if [ -n "$filepath" ]; then
        # Skip empty or directory markers
        if [[ "$filepath" == */ ]]; then
            continue
        fi

        # Determine category
        category=$(categorize_file "$filepath")

        # Create new path
        filename=$(basename "$filepath")
        new_path="s3://$TARGET_BUCKET/$category/$filename"

        echo "Moving $filepath to $new_path" | tee -a "$LOG_FILE"

        # Copy file to new location
        s3cmd cp "s3://$SOURCE_BUCKET/$filepath" "$new_path" >> "$LOG_FILE" 2>&1
    fi
done

echo "Migration completed at $(date)" | tee -a "$LOG_FILE"

# Verify migration
echo -e "\nVerifying migration..." | tee -a "$LOG_FILE"
echo "Source bucket contents:" | tee -a "$LOG_FILE"
s3cmd du -H "s3://$SOURCE_BUCKET/" | tee -a "$LOG_FILE"
echo "Target bucket contents:" | tee -a "$LOG_FILE"
s3cmd du -H "s3://$TARGET_BUCKET/" | tee -a "$LOG_FILE"

echo "Migration script completed. Check $LOG_FILE for details."