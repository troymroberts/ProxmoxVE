#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ) - Modified for Enterprise Edition Support
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/odoo/odoo

APP="Odoo"
var_tags="${var_tags:-business,erp}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  
  if [[ ! -f /opt/"${APPLICATION}"_version.txt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  
  msg_info "Updating ${APP}"
  
  # Detect installation type
  if [ -d "/opt/odoo/community" ]; then
    # Enterprise installation - update via git
    cd /opt/odoo/community
    sudo -u odoo git pull
    
    if [ -d "/opt/odoo/enterprise" ]; then
      cd /opt/odoo/enterprise
      sudo -u odoo git pull
      echo "$(date '+%Y-%m-%d')-enterprise" > /opt/"${APPLICATION}"_version.txt
    fi
    
    systemctl restart odoo
    msg_ok "Updated ${APP} Enterprise"
  else
    # Community installation - check for package updates
    RELEASE=$(curl -fsSL https://nightly.odoo.com/ | grep -oE 'href="[0-9]+\.[0-9]+/nightly"' | head -n1 | cut -d'"' -f2 | cut -d/ -f1)
    LATEST_VERSION=$(curl -fsSL "https://nightly.odoo.com/${RELEASE}/nightly/deb/" |
      grep -oP "odoo_${RELEASE}\.\d+_all\.deb" |
      sed -E "s/odoo_(${RELEASE}\.[0-9]+)_all\.deb/\1/" |
      sort -V |
      tail -n1)
    
    if [[ "${LATEST_VERSION}" != "$(cat /opt/"${APPLICATION}"_version.txt)" ]]; then
      curl -fsSL https://nightly.odoo.com/${RELEASE}/nightly/deb/odoo_${RELEASE}.latest_all.deb -o /opt/odoo.deb
      apt install -y /opt/odoo.deb
      rm -f /opt/odoo.deb
      echo "${LATEST_VERSION}" > /opt/"${APPLICATION}"_version.txt
      systemctl restart odoo
      msg_ok "Updated ${APP} to ${LATEST_VERSION}"
    else
      msg_ok "No update required. ${APP} is already at ${LATEST_VERSION}"
    fi
  fi
  
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8069${CL}"