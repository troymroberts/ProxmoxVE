#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ) - Modified for Enterprise Edition Support
# License: MIT |  https://github.com/tteck/Proxmox/raw/main/LICENSE
# Source: https://github.com/odoo/odoo

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Function to detect system resources
detect_system_resources() {
    local cpu_cores ram_mb
    
    # Detect CPU cores (container-aware)
    if [ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ] && [ -r /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
        local cpu_quota=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
        local cpu_period=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
        if [ "$cpu_quota" -gt 0 ] && [ "$cpu_period" -gt 0 ]; then
            cpu_cores=$((cpu_quota / cpu_period))
        else
            cpu_cores=$(nproc)
        fi
    else
        cpu_cores=$(nproc)
    fi
    
    # Detect RAM (container-aware)
    if [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        local memory_limit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
        if [ "$memory_limit" -lt 9223372036854775807 ]; then
            ram_mb=$((memory_limit / 1024 / 1024))
        else
            ram_mb=$(free -m | awk 'NR==2{print $2}')
        fi
    else
        ram_mb=$(free -m | awk 'NR==2{print $2}')
    fi
    
    echo "CPU_CORES=$cpu_cores"
    echo "RAM_MB=$ram_mb"
}

# Function to calculate optimal worker configuration
calculate_workers() {
    local cpu_cores=$1
    local ram_mb=$2
    local max_users=${3:-30}
    
    # Calculate workers: (CPU cores * 2) + 1, but consider memory
    local max_workers=$(((cpu_cores * 2) + 1))
    local user_workers=$((max_users / 6))
    
    # Choose minimum for safety
    local workers=$max_workers
    [ $user_workers -lt $workers ] && workers=$user_workers
    
    # Memory validation (300MB per worker conservative estimate)
    local required_memory=$((workers * 300))
    local available_memory=$((ram_mb * 80 / 100))
    
    if [ $required_memory -gt $available_memory ]; then
        workers=$((available_memory / 300))
    fi
    
    # Ensure minimum values
    [ $workers -lt 1 ] && workers=1
    
    # Cron workers
    local cron_workers=1
    [ $cpu_cores -gt 4 ] && cron_workers=2
    
    echo "WORKERS=$workers"
    echo "CRON_WORKERS=$cron_workers"
    echo "MAX_WORKERS_SUGGESTED=$max_workers"
}

# Function to prompt for edition selection
select_edition() {
    # Use environment variable if set, otherwise prompt
    if [ -n "$ODOO_EDITION" ]; then
        echo "Using pre-configured edition: $ODOO_EDITION"
        return
    fi
    
    echo ""
    echo "==================================="
    echo "      Odoo Edition Selection"
    echo "==================================="
    echo "1) Community Edition (Free)"
    echo "2) Enterprise Edition (Requires subscription & GitHub access)"
    echo ""
    read -p "Select edition [1-2]: " EDITION_CHOICE
    
    case $EDITION_CHOICE in
        1)
            ODOO_EDITION="community"
            ;;
        2)
            ODOO_EDITION="enterprise"
            echo ""
            echo "Enterprise edition requires:"
            echo "- Valid Odoo subscription"
            echo "- GitHub Personal Access Token with access to odoo/enterprise repo"
            echo "- Your GitHub account must be added to the Odoo partner dashboard"
            echo ""
            read -p "Do you have GitHub access to odoo/enterprise? (y/n): " CONFIRM
            if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
                echo "Please contact Odoo to get GitHub access, then re-run this script."
                exit 1
            fi
            ;;
        *)
            echo "Invalid selection. Defaulting to Community Edition."
            ODOO_EDITION="community"
            ;;
    esac
}

# Function to get GitHub token for enterprise
get_github_token() {
    if [ "$ODOO_EDITION" = "enterprise" ]; then
        # Use environment variable if set, otherwise prompt
        if [ -n "$GITHUB_TOKEN" ]; then
            echo "Using pre-configured GitHub token"
        else
            echo ""
            echo "Enter your GitHub Personal Access Token:"
            echo "(Token will not be displayed for security)"
            read -s GITHUB_TOKEN
            echo ""
        fi
        
        if [ -z "$GITHUB_TOKEN" ]; then
            echo "Error: GitHub token is required for enterprise installation"
            exit 1
        fi
        
        # Test GitHub access
        if ! curl -s -H "Authorization: token $GITHUB_TOKEN" \
            https://api.github.com/repos/odoo/enterprise >/dev/null 2>&1; then
            echo "Error: Cannot access odoo/enterprise repository with provided token"
            echo "Please check your token and repository access"
            exit 1
        fi
        
        echo "GitHub authentication successful"
    fi
}

# Function to configure resource optimization
configure_optimization() {
    # Use environment variable if set, otherwise prompt
    if [ -n "$AUTO_OPTIMIZE" ]; then
        echo "Using pre-configured optimization setting: $AUTO_OPTIMIZE"
    else
        echo ""
        read -p "Enable automatic resource optimization? (y/n) [y]: " AUTO_OPTIMIZE
        AUTO_OPTIMIZE=${AUTO_OPTIMIZE:-y}
    fi
    
    if [[ $AUTO_OPTIMIZE =~ ^[Yy]$ ]]; then
        eval $(detect_system_resources)
        eval $(calculate_workers $CPU_CORES $RAM_MB)
        
        echo ""
        echo "==================================="
        echo "      System Resource Detection"
        echo "==================================="
        echo "Detected CPU Cores: $CPU_CORES"
        echo "Detected RAM: ${RAM_MB}MB"
        echo "Recommended Workers: $WORKERS"
        echo "Recommended Cron Workers: $CRON_WORKERS"
        echo "==================================="
        echo ""
        
        OPTIMIZE_CONFIG="true"
    else
        WORKERS=2
        CRON_WORKERS=1
        OPTIMIZE_CONFIG="false"
    fi
}

# Get user preferences
select_edition
get_github_token
configure_optimization

msg_info "Installing Dependencies"
$STD apt-get install -y \
  build-essential \
  make \
  git \
  python3-dev \
  python3-pip \
  libxml2-dev \
  libxslt1-dev \
  libldap2-dev \
  libsasl2-dev \
  libtiff5-dev \
  libjpeg8-dev \
  libopenjp2-7-dev \
  zlib1g-dev \
  libfreetype6-dev \
  liblcms2-dev \
  libwebp-dev \
  libharfbuzz-dev \
  libfribidi-dev \
  libxcb1-dev \
  libpq-dev \
  wkhtmltopdf
msg_ok "Installed Dependencies"

if [ "$ODOO_EDITION" = "enterprise" ]; then
    msg_info "Installing Odoo Enterprise Edition"
    
    # Create odoo user and directories
    $STD useradd -m -U -r -d /opt/odoo -s /bin/bash odoo
    
    # Clone community repository
    $STD sudo -u odoo git clone https://github.com/odoo/odoo.git --depth 1 --branch 17.0 /opt/odoo/community
    
    # Clone enterprise repository with authentication
    $STD sudo -u odoo git clone "https://x-access-token:$GITHUB_TOKEN@github.com/odoo/enterprise.git" --depth 1 --branch 17.0 /opt/odoo/enterprise
    
    # Create custom addons directory
    $STD sudo -u odoo mkdir -p /opt/odoo/custom-addons
    
    # Install Python dependencies
    $STD sudo -u odoo python3 -m pip install --upgrade pip
    $STD sudo -u odoo python3 -m pip install -r /opt/odoo/community/requirements.txt
    
    # Clean up token from memory
    unset GITHUB_TOKEN
    
    LATEST_VERSION="17.0-enterprise"
    ADDONS_PATH="/opt/odoo/enterprise,/opt/odoo/community/addons,/opt/odoo/custom-addons"
    ODOO_BIN="/opt/odoo/community/odoo-bin"
    
    msg_ok "Installed Odoo Enterprise Edition"
else
    msg_info "Installing Odoo Community Edition"
    
    RELEASE=$(curl -fsSL https://nightly.odoo.com/ | grep -oE 'href="[0-9]+\.[0-9]+/nightly"' | head -n1 | cut -d'"' -f2 | cut -d/ -f1)
    LATEST_VERSION=$(curl -fsSL "https://nightly.odoo.com/${RELEASE}/nightly/deb/" |
      grep -oP "odoo_${RELEASE}\.\d+_all\.deb" |
      sed -E "s/odoo_(${RELEASE}\.[0-9]+)_all\.deb/\1/" |
      sort -V |
      tail -n1)

    curl -fsSL https://nightly.odoo.com/${RELEASE}/nightly/deb/odoo_${RELEASE}.latest_all.deb -o /opt/odoo.deb
    $STD apt install -y /opt/odoo.deb
    
    ADDONS_PATH="/usr/lib/python3/dist-packages/odoo/addons"
    ODOO_BIN="/usr/bin/odoo"
    
    msg_ok "Installed Odoo Community Edition"
fi

msg_info "Setup PostgreSQL Database"
DB_NAME="odoo"
DB_USER="odoo_usr"
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
$STD sudo -u postgres psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;"
$STD sudo -u postgres psql -c "ALTER USER $DB_USER WITH SUPERUSER;"
{
  echo "Odoo-Credentials"
  echo -e "Odoo Edition: $ODOO_EDITION"
  echo -e "Odoo Database User: $DB_USER"
  echo -e "Odoo Database Password: $DB_PASS"
  echo -e "Odoo Database Name: $DB_NAME"
  if [ "$OPTIMIZE_CONFIG" = "true" ]; then
    echo -e "Workers: $WORKERS"
    echo -e "Cron Workers: $CRON_WORKERS"
    echo -e "Detected CPU Cores: $CPU_CORES"
    echo -e "Detected RAM: ${RAM_MB}MB"
  fi
} >>~/odoo.creds
msg_ok "Setup PostgreSQL"

msg_info "Configuring Odoo"

if [ "$ODOO_EDITION" = "enterprise" ]; then
    # Create configuration directory
    mkdir -p /etc/odoo
    
    # Create configuration file for source installation
    cat > /etc/odoo/odoo.conf << EOF
[options]
addons_path = $ADDONS_PATH
admin_passwd = $(openssl rand -base64 32)
db_host = localhost
db_port = 5432
db_user = $DB_USER
db_password = $DB_PASS
db_name = $DB_NAME
xmlrpc_port = 8069
longpolling_port = 8072
workers = $WORKERS
max_cron_threads = $CRON_WORKERS
limit_memory_soft = 671088640
limit_memory_hard = 805306368
limit_time_cpu = 600
limit_time_real = 1200
limit_request = 8192
log_level = info
logfile = /var/log/odoo/odoo.log
EOF

    # Create log directory
    mkdir -p /var/log/odoo
    chown odoo:odoo /var/log/odoo
    chown odoo:odoo /etc/odoo/odoo.conf
    
    # Create systemd service for source installation
    cat > /etc/systemd/system/odoo.service << EOF
[Unit]
Description=Odoo Enterprise
Documentation=http://www.odoo.com
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=$ODOO_BIN -c /etc/odoo/odoo.conf
StandardOutput=journal+console
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    $STD systemctl daemon-reload
    $STD systemctl enable odoo
    
    # Initialize database
    $STD sudo -u odoo $ODOO_BIN -c /etc/odoo/odoo.conf -d $DB_NAME -i base --stop-after-init
else
    # Configure existing installation
    sed -i \
      -e "s|^;*db_host *=.*|db_host = localhost|" \
      -e "s|^;*db_port *=.*|db_port = 5432|" \
      -e "s|^;*db_user *=.*|db_user = $DB_USER|" \
      -e "s|^;*db_password *=.*|db_password = $DB_PASS|" \
      /etc/odoo/odoo.conf
    
    if [ "$OPTIMIZE_CONFIG" = "true" ]; then
        # Add worker configuration to existing config
        sed -i \
          -e "s|^;*workers *=.*|workers = $WORKERS|" \
          -e "s|^;*max_cron_threads *=.*|max_cron_threads = $CRON_WORKERS|" \
          /etc/odoo/odoo.conf
        
        # Add if not exists
        grep -q "^workers" /etc/odoo/odoo.conf || echo "workers = $WORKERS" >> /etc/odoo/odoo.conf
        grep -q "^max_cron_threads" /etc/odoo/odoo.conf || echo "max_cron_threads = $CRON_WORKERS" >> /etc/odoo/odoo.conf
    fi
    
    $STD sudo -u odoo odoo -c /etc/odoo/odoo.conf -d $DB_NAME -i base --stop-after-init
fi

echo "${LATEST_VERSION}" >/opt/${APPLICATION}_version.txt
msg_ok "Configured Odoo"

msg_info "Starting Odoo"
$STD systemctl start odoo
msg_ok "Started Odoo"

motd_ssh
customize

msg_info "Cleaning up"
if [ "$ODOO_EDITION" = "community" ]; then
    rm -f /opt/odoo.deb
fi
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"

echo ""
echo "=================================="
echo "    Odoo Installation Complete"
echo "=================================="
echo "Edition: $ODOO_EDITION"
echo "Version: $LATEST_VERSION"
echo "Web Interface: http://$(hostname -I | awk '{print $1}'):8069"
echo "Database: $DB_NAME"
if [ "$OPTIMIZE_CONFIG" = "true" ]; then
    echo "Workers: $WORKERS"
    echo "Cron Workers: $CRON_WORKERS"
fi
echo ""
echo "Credentials saved to: ~/odoo.creds"
echo "=================================="