#!/bin/bash

# Static Configuration
WORKSPACE_DIR="/opt/storage-migration"
DASHBOARD_DIR="${WORKSPACE_DIR}/dashboard"
LOG_DIR="${WORKSPACE_DIR}/logs"
NGINX_CONFIG_DIR="/etc/nginx/conf.d"
SSL_DIR="/etc/letsencrypt"

# Domain and IP Configuration
VPS_DOMAIN="toowired.solutions"
VPS_IP="208.87.135.212"
INTERNAL_IP=$(hostname -I | awk '{print $1}')
INTERNAL_NETWORK="208.87.135.0/24"  # Subnet for the VPS network

# Create required directories
mkdir -p "${WORKSPACE_DIR}"/{dashboard,logs,transfer_metrics,predictions/resources,status}

# Setup Python virtual environment
echo "Setting up Python virtual environment..."
cd "${DASHBOARD_DIR}"
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Install Node.js and npm if not present
if ! command -v node &> /dev/null; then
    echo "Installing Node.js and npm..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# Setup frontend
echo "Setting up frontend..."
cd frontend

# Configure environment with domain settings
echo "Configuring frontend environment..."
cat > .env << EOF
REACT_APP_API_BASE=https://${VPS_DOMAIN}/dashboard/api
REACT_APP_WS_BASE=wss://${VPS_DOMAIN}/dashboard
EOF

# Install dependencies and build
npm install
npm run build

# Setup systemd service for the backend
echo "Setting up systemd service..."
sudo tee /etc/systemd/system/storage-dashboard.service << EOF
[Unit]
Description=Storage Migration Dashboard
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=${DASHBOARD_DIR}
Environment="PATH=${DASHBOARD_DIR}/venv/bin"
Environment="WORKSPACE_DIR=${WORKSPACE_DIR}"
Environment="VPS_DOMAIN=${VPS_DOMAIN}"
Environment="VPS_IP=${VPS_IP}"
ExecStart=${DASHBOARD_DIR}/venv/bin/gunicorn \
    --bind unix:/run/storage-dashboard.sock \
    --workers 4 \
    --threads 4 \
    --umask 007 \
    --group www-data \
    app:app
Restart=always
StandardOutput=append:${LOG_DIR}/dashboard.log
StandardError=append:${LOG_DIR}/dashboard.error.log

[Install]
WantedBy=multi-user.target
EOF

# Create security configuration
echo "Setting up security configuration..."
sudo tee "${NGINX_CONFIG_DIR}/security-headers.conf" << EOF
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
add_header Content-Security-Policy "default-src 'self' https: http: ws: wss: data: 'unsafe-inline' 'unsafe-eval';" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
EOF

# Setup nginx for serving the frontend with SSL
echo "Setting up nginx..."
sudo tee /etc/nginx/sites-available/storage-dashboard << EOF
# Rate limiting zone
limit_req_zone \$binary_remote_addr zone=dashboard_limit:10m rate=10r/s;

# Upstream for gunicorn
upstream dashboard_backend {
    server unix:/run/storage-dashboard.sock fail_timeout=0;
}

# HTTP redirect to HTTPS
server {
    listen 80;
    server_name ${VPS_DOMAIN};

    location /dashboard {
        return 301 https://\$server_name\$request_uri;
    }
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name ${VPS_DOMAIN};

    # SSL configuration
    ssl_certificate ${SSL_DIR}/live/${VPS_DOMAIN}/fullchain.pem;
    ssl_certificate_key ${SSL_DIR}/live/${VPS_DOMAIN}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Security headers
    include ${NGINX_CONFIG_DIR}/security-headers.conf;

    # Dashboard location under /dashboard path
    location /dashboard {
        alias ${DASHBOARD_DIR}/frontend/build;
        try_files \$uri \$uri/ /dashboard/index.html;

        # Basic auth for additional security
        auth_basic "Storage Migration Dashboard";
        auth_basic_user_file /etc/nginx/.htpasswd;

        # Rate limiting
        limit_req zone=dashboard_limit burst=20 nodelay;
    }

    # API proxy
    location /dashboard/api {
        auth_basic "Storage Migration Dashboard";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://dashboard_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Rate limiting
        limit_req zone=dashboard_limit burst=10 nodelay;
    }

    # WebSocket proxy
    location /dashboard/events {
        auth_basic "Storage Migration Dashboard";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://dashboard_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Deny access to . files
    location ~ /\. {
        deny all;
    }
}
EOF

# Create basic auth credentials
echo "Setting up basic authentication..."
if [ ! -f /etc/nginx/.htpasswd ]; then
    sudo apt-get install -y apache2-utils
    # Generate a random password
    DASHBOARD_PASS=$(openssl rand -base64 12)
    sudo htpasswd -bc /etc/nginx/.htpasswd admin "${DASHBOARD_PASS}"
    echo "Generated admin credentials:"
    echo "Username: admin"
    echo "Password: ${DASHBOARD_PASS}"
fi

# Enable the site and remove default if exists
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/storage-dashboard /etc/nginx/sites-enabled/

# Verify nginx configuration
sudo nginx -t

# Setup SSL certificate if not exists
if [ ! -d "${SSL_DIR}/live/${VPS_DOMAIN}" ]; then
    echo "Setting up SSL certificate..."
    sudo apt-get install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d ${VPS_DOMAIN} --non-interactive --agree-tos --email admin@${VPS_DOMAIN}
fi

# Restart services
echo "Restarting services..."
sudo systemctl daemon-reload
sudo systemctl enable storage-dashboard
sudo systemctl restart storage-dashboard
sudo systemctl restart nginx

echo "Dashboard deployment complete!"
echo "Access the dashboard at https://${VPS_DOMAIN}/dashboard"
echo "API endpoint: https://${VPS_DOMAIN}/dashboard/api"
echo "Check logs at ${LOG_DIR}/dashboard.log"

# Security reminder
echo -e "\nSecurity Notes:"
echo "1. Dashboard is accessible at /dashboard path"
echo "2. Basic authentication is enabled"
echo "3. SSL/TLS encryption is enabled"
echo "4. Rate limiting is configured"
echo "5. Security headers are implemented"
echo "6. All traffic is encrypted"

# Save credentials to a secure file
echo -e "\nSaving credentials to ${WORKSPACE_DIR}/dashboard_credentials.txt"
cat > "${WORKSPACE_DIR}/dashboard_credentials.txt" << EOF
Dashboard Credentials
====================
URL: https://${VPS_DOMAIN}/dashboard
Username: admin
Password: ${DASHBOARD_PASS}

Keep this file secure!
Generated on: $(date)
EOF

chmod 600 "${WORKSPACE_DIR}/dashboard_credentials.txt"