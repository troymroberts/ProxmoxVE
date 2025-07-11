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

# Odoo-specific variables
var_edition="${var_edition:-community}"
var_auto_optimize="${var_auto_optimize:-true}"
var_github_token="${var_github_token:-}"

header_info "$APP"
variables
color
catch_errors

function default_settings() {
    var_edition="community"
    var_auto_optimize="true"
    echo -e "${DGN}Using Default Settings${CL}"
    echo -e "${DGN}Edition: ${BGN}Community${CL}"
    echo -e "${DGN}Auto-Optimize: ${BGN}Enabled${CL}"
    echo -e "${BL}Creating a ${GN}$APP${BL} container${CL}"
}

function advanced_settings() {
    echo -e "${RD}Using Advanced Settings${CL}"
    echo -e "${YW}Type Privileged, or Press [ENTER] for Default ${BL}Unprivileged${CL}"
    read -p "Select: " -e -i "$var_unprivileged" var_unprivileged
    if ! [[ "$var_unprivileged" =~ ^(1|0)$ ]]; then
        echo -e "${RD}Invalid Input. Using Default ${var_unprivileged}${CL}"
    fi
    echo -e "${DGN}Privileged: ${BGN}$var_unprivileged${CL}"
    
    echo -e "${YW}Type Distribution, or Press [ENTER] for Default ${BL}$var_os${CL}"
    read -p "Select: " -e -i "$var_os" var_os
    if ! [[ "$var_os" =~ ^(debian|ubuntu)$ ]]; then
        echo -e "${RD}Invalid Input. Using Default ${var_os}${CL}"
        var_os="debian"
    fi
    echo -e "${DGN}Distribution: ${BGN}$var_os${CL}"
    
    echo -e "${YW}Type Version, or Press [ENTER] for Default ${BL}$var_version${CL}"
    read -p "Select: " -e -i "$var_version" var_version
    echo -e "${DGN}Version: ${BGN}$var_version${CL}"
    
    echo -e "${YW}Allocate CPU cores, or Press [ENTER] for Default ${BL}$var_cpu${CL}"
    read -p "Cores: " -e -i "$var_cpu" var_cpu
    if ! [[ "$var_cpu" =~ ^[0-9]+$ ]]; then
        echo -e "${RD}Invalid Input. Using Default ${var_cpu}${CL}"
        var_cpu="4"
    fi
    echo -e "${DGN}Allocated: ${BGN}$var_cpu${CL} cores"
    
    echo -e "${YW}Allocate RAM in MiB, or Press [ENTER] for Default ${BL}$var_ram${CL}"
    read -p "RAM: " -e -i "$var_ram" var_ram
    if ! [[ "$var_ram" =~ ^[0-9]+$ ]]; then
        echo -e "${RD}Invalid Input. Using Default ${var_ram}${CL}"
        var_ram="4096"
    fi
    echo -e "${DGN}Allocated: ${BGN}$var_ram${CL} MiB RAM"
    
    echo -e "${YW}Allocate Disk in GB, or Press [ENTER] for Default ${BL}$var_disk${CL}"
    read -p "Disk: " -e -i "$var_disk" var_disk
    if ! [[ "$var_disk" =~ ^[0-9]+$ ]]; then
        echo -e "${RD}Invalid Input. Using Default ${var_disk}${CL}"
        var_disk="20"
    fi
    echo -e "${DGN}Allocated: ${BGN}$var_disk${CL} GB${CL}"
    
    echo -e "${YW}Select Odoo Edition${CL}"
    echo -e "${YW}1) Community Edition (Free)${CL}"
    echo -e "${YW}2) Enterprise Edition (Requires subscription & GitHub access)${CL}"
    read -p "Edition [1-2]: " edition_choice
    case $edition_choice in
        1)
            var_edition="community"
            echo -e "${DGN}Edition: ${BGN}Community${CL}"
            ;;
        2)
            var_edition="enterprise"
            echo -e "${DGN}Edition: ${BGN}Enterprise${CL}"
            echo -e "${YW}Enterprise edition requires:${CL}"
            echo -e "${YW}• Valid Odoo subscription${CL}"
            echo -e "${YW}• GitHub Personal Access Token${CL}"
            echo -e "${YW}• Access to odoo/enterprise repository${CL}"
            echo ""
            echo -e "${YW}Enter GitHub Personal Access Token (optional - can be set during installation):${CL}"
            read -s -p "Token: " var_github_token
            echo ""
            if [ -n "$var_github_token" ]; then
                echo -e "${DGN}GitHub Token: ${BGN}[SET]${CL}"
            else
                echo -e "${DGN}GitHub Token: ${YW}[Will prompt during installation]${CL}"
            fi
            ;;
        *)
            echo -e "${RD}Invalid Selection. Using Default Community Edition${CL}"
            var_edition="community"
            ;;
    esac
    
    echo -e "${YW}Enable automatic resource optimization? (y/n), or Press [ENTER] for Default ${BL}y${CL}"
    read -p "Auto-Optimize: " auto_opt
    case $auto_opt in
        [Nn]*)
            var_auto_optimize="false"
            echo -e "${DGN}Auto-Optimize: ${BGN}Disabled${CL}"
            ;;
        *)
            var_auto_optimize="true"
            echo -e "${DGN}Auto-Optimize: ${BGN}Enabled${CL}"
            ;;
    esac
    
    echo -e "${BL}Creating a ${GN}$APP${BL} container${CL}"
}

function install_script() {
    if [[ "$VERBOSE" == "yes" ]]; then set -x; fi
    if [[ "$var_os" == "debian" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update &>/dev/null
        apt-get -y install curl &>/dev/null
        apt-get -y install sudo &>/dev/null
        apt-get -y install postgresql &>/dev/null
        apt-get -y install postgresql-contrib &>/dev/null
    elif [[ "$var_os" == "ubuntu" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update &>/dev/null
        apt-get -y install curl &>/dev/null
        apt-get -y install sudo &>/dev/null
        apt-get -y install postgresql &>/dev/null
        apt-get -y install postgresql-contrib &>/dev/null
    fi
    
    export FUNCTIONS_FILE_PATH="$(curl -fsSL "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func")"
    export APPLICATION="$APP"
    export VERBOSE="$VERBOSE"
    export SSH_ROOT="${SSH_ROOT}"
    export CTID="$CTID"
    export PCT_OSTYPE="$PCT_OSTYPE"
    export PCT_OSVERSION="$PCT_OSVERSION"
    export PCT_DISK_SIZE="$PCT_DISK_SIZE"
    export PCT_OPTIONS="$PCT_OPTIONS"
    export PCT_CORES="$PCT_CORES"
    export PCT_RAM="$PCT_RAM"
    export PCT_PASSWORD="$PCT_PASSWORD"
    export VMID="$VMID"
    
    # Export Odoo-specific variables
    export ODOO_EDITION="$var_edition"
    export AUTO_OPTIMIZE="$var_auto_optimize"
    export GITHUB_TOKEN="$var_github_token"
    
    bash -c "$(curl -fsSL "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/odoo-install.sh")" || exit
}

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    
    if [[ ! -f /opt/"${APP}"_version.txt ]]; then
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
            echo "$(date '+%Y-%m-%d')-enterprise" > /opt/"${APP}"_version.txt
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
        
        if [[ "${LATEST_VERSION}" != "$(cat /opt/"${APP}"_version.txt)" ]]; then
            curl -fsSL https://nightly.odoo.com/${RELEASE}/nightly/deb/odoo_${RELEASE}.latest_all.deb -o /opt/odoo.deb
            apt install -y /opt/odoo.deb
            rm -f /opt/odoo.deb
            echo "${LATEST_VERSION}" > /opt/"${APP}"_version.txt
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