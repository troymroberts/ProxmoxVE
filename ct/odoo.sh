#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# Co-Author: Troy M. Roberts
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE"
color
verb_ip6
catch_errors
setting_up_container
update_os

# Odoo Version
Odoo_Version="17.0"

# Set the description for the LXC
if [ -z "$CT_DESCRIPTION" ]; then
  CT_DESCRIPTION="Odoo is a suite of open source business apps."
fi

# Define the installation message
msg_info "Installing Dependencies"
$STD apt-get install -y wget gdebi
msg_ok "Installed Dependencies"

# Ask the user if they want to install Odoo Enterprise
read -p "Will you be using Odoo Enterprise? (y/N) " -n 1 -r ODOO_ENTERPRISE
echo "" # Move to a new line

if [[ $ODOO_ENTERPRISE =~ ^[Yy]$ ]]; then
  # ODOO ENTERPRISE INSTALLATION
  msg_info "Setting up Odoo Enterprise..."
  read -p "Please enter your Odoo Enterprise Subscription Code: " ODOO_ENTERPRISE_CODE

  msg_info "Adding Odoo Enterprise repository"
  wget -O - https://nightly.odoo.com/odoo.key | gpg --dearmor | tee /usr/share/keyrings/odoo.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/odoo.gpg] https://nightly.odoo.com/${Odoo_Version}/enterprise/debian/ ./" > /etc/apt/sources.list.d/odoo.list
  $STD apt-get update
  msg_ok "Odoo Enterprise repository added"

  msg_info "Installing Odoo Enterprise Package"
  $STD apt-get install -y odoo
  msg_ok "Installed Odoo Enterprise"

  msg_info "Configuring Odoo Enterprise"
  # The enterprise path is automatically added by the package, but we ensure it's correct.
  # The addons_path is typically /usr/lib/python3/dist-packages/odoo/addons for the deb package.
  sed -i "s|^addons_path = .*|addons_path = /opt/odoo/enterprise/addons,/usr/lib/python3/dist-packages/odoo/addons|" /etc/odoo.conf
  
  # Add the subscription code if provided
  if [ -n "$ODOO_ENTERPRISE_CODE" ]; then
    echo "subscriber_code = ${ODOO_ENTERPRISE_CODE}" >> /etc/odoo.conf
    msg_ok "Added subscription code to odoo.conf"
  fi

  msg_info "Restarting Odoo Service"
  systemctl restart odoo
  msg_ok "Odoo Enterprise setup complete"

else
  # ODOO COMMUNITY INSTALLATION (Original Logic)
  msg_info "Setting up Odoo Community..."
  
  msg_info "Adding Odoo Community repository"
  wget -O - https://nightly.odoo.com/odoo.key | gpg --dearmor | tee /usr/share/keyrings/odoo.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/odoo.gpg] http://nightly.odoo.com/${Odoo_Version}/nightly/deb/ ./" > /etc/apt/sources.list.d/odoo.list
  $STD apt-get update
  msg_ok "Odoo Community repository added"

  msg_info "Installing Odoo Community Package"
  $STD apt-get install -y odoo
  msg_ok "Installed Odoo Community"

  msg_info "Restarting Odoo Service"
  systemctl restart odoo
  msg_ok "Odoo Community setup complete"
fi

# Install PostgreSQL client for database management
msg_info "Installing PostgreSQL Client"
$STD apt-get install -y postgresql-client
msg_ok "Installed PostgreSQL Client"

motd_ssh
customize

# Cleanup
$STD apt-get autoremove
$STD apt-get autoclean

# Get IP address
IP=$(hostname -I | awk '{print $1}')

# Display completion message
msg_info "Successfully Installed Odoo"
echo -e "Odoo is listening on all interfaces at port 8069"
echo -e "\n It is recommended to use a reverse proxy to access Odoo."
echo -e " For example, http://${IP}:8069"

# The following lines are sourced from the main script and must be present
# --- start of sourced section ---
# cat <<EOF is a heredoc, it prints everything until the final EOF
cat <<EOF > /etc/motd
  ____      __          
 / __ \____/ /___  ____ 
/ / / / __  / __ \/ __ \
/ /_/ / /_/ / /_/ / /_/ /
\____/\__,_/\____/\____/ 

EOF
# --- end of sourced section ---

# This function is not part of the LXC script but is called by the main helper script
function header_info {
  cat <<EOF
  Odoo
  is a suite of open source business apps that cover all your company needs:
  CRM, eCommerce, accounting, inventory, point of sale, project management, etc.
EOF
}

# This is the function you were missing
function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$LXC_ID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

# This function is called by the main helper script
function update_script() {
  header_info
  # Check if the script is outdated
  if [[ ! -f /etc/odoo.conf ]]; then
    msg_error "Cannot find Odoo configuration file. Aborting."
    exit 1
  fi
  # Update logic would go here if needed in the future
  msg_info "Updating Odoo is handled by 'apt-get upgrade'."
  echo -e "To update Odoo, run the following commands inside the container:
  apt-get update
  apt-get upgrade"
  exit 0
}

# The main helper script calls this function
start_script