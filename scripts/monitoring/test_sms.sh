#!/bin/bash

# Load configuration
CONFIG_FILE="$(dirname "$0")/config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found!"
    exit 1
fi

# Test SMS
curl -X POST "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID/Messages.json" \
    --data-urlencode "To=$ADMIN_PHONE_NUMBER" \
    --data-urlencode "From=$TWILIO_FROM_NUMBER" \
    --data-urlencode "Body=Test SMS from VPS Monitoring" \
    -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN"