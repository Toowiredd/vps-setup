#!/bin/bash

# Load configuration
CONFIG_FILE="$(dirname "$0")/config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found!"
    exit 1
fi

# Check for required commands
for cmd in bc curl mail; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: Required command '$cmd' not found. Please install it."
        exit 1
    fi
done

# Configuration
LOG_DIR="/var/log/system_monitor"
REPORT_FILE="$LOG_DIR/status_report.log"
BUCKET_NAME="tysbucket"
MAX_LOG_AGE=7  # days

# Function to compare numbers (fallback if bc fails)
compare_numbers() {
    local val1=$1
    local op=$2
    local val2=$3

    if command -v bc &> /dev/null; then
        if [ "$op" = ">" ]; then
            [ $(echo "$val1 > $val2" | bc -l) -eq 1 ]
        elif [ "$op" = "<" ]; then
            [ $(echo "$val1 < $val2" | bc -l) -eq 1 ]
        fi
    else
        # Fallback to bash arithmetic (less precise but works without bc)
        val1=${val1%.*}
        val2=${val2%.*}
        if [ "$op" = ">" ]; then
            [ "$val1" -gt "$val2" ]
        elif [ "$op" = "<" ]; then
            [ "$val1" -lt "$val2" ]
        fi
    fi
}

# Severity levels and repeat counts
declare -A SEVERITY_REPEATS=(
    ["CRITICAL"]=3
    ["HIGH"]=2
    ["MEDIUM"]=1
    ["LOW"]=1
)

# Function to send SMS via Twilio
send_sms() {
    local message="$1"
    if ! curl -X POST "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID/Messages.json" \
        --data-urlencode "To=$ADMIN_PHONE_NUMBER" \
        --data-urlencode "From=$TWILIO_FROM_NUMBER" \
        --data-urlencode "Body=$message" \
        -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" > /dev/null 2>&1; then
        echo "Failed to send SMS notification" >> "$REPORT_FILE"
    fi
}

# Function to send notification
send_notification() {
    local subject="$1"
    local message="$2"
    local severity="$3"
    local repeat_count=${SEVERITY_REPEATS[$severity]}

    # Send emails
    for ((i=1; i<=$repeat_count; i++)); do
        if ! echo "$message" | mail -s "[$severity] $subject - Alert $i/$repeat_count" "$ADMIN_EMAIL"; then
            echo "Failed to send email notification" >> "$REPORT_FILE"
        fi

        # Send SMS only for CRITICAL alerts
        if [ "$severity" = "CRITICAL" ]; then
            send_sms "[$severity] $subject: $message"
        fi

        # Only sleep if we have more messages to send
        if [ $i -lt $repeat_count ]; then
            sleep 300  # 5-minute delay between repeated alerts
        fi
    done
}

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Timestamp for this run
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
echo "=== System Status Report - $TIMESTAMP ===" > "$REPORT_FILE"

# Memory Check with Severity
total_mem=$(free | awk '/Mem:/ {print $2}')
used_mem=$(free | awk '/Mem:/ {print $3}')
mem_usage=$(( (used_mem * 100) / total_mem ))
echo "Memory Usage: $mem_usage%" >> "$REPORT_FILE"

if compare_numbers "$mem_usage" ">" "90"; then
    send_notification "High Memory Usage" "Memory usage is at $mem_usage%" "CRITICAL"
elif compare_numbers "$mem_usage" ">" "80"; then
    send_notification "Memory Warning" "Memory usage is at $mem_usage%" "HIGH"
fi

# Rest of your existing monitoring code...