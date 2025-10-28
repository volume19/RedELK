#!/bin/bash
#############################################################################
# RedELK Filebeat Deployment Script - Cobalt Strike C2 Server (ENHANCED)
# Purpose: Install and configure filebeat on Cobalt Strike teamserver
# Features: Complete cleanup, nested field structure, visual feedback
# Usage: sudo bash deploy-filebeat-c2.sh
#############################################################################

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }

error_exit() {
    log_error "$1"
    exit 1
}

# Progress bar
progress() {
    local duration=$1
    local msg=$2
    echo -ne "${CYAN}${msg}${NC} ["
    for ((i=0; i<duration; i++)); do
        echo -ne "${GREEN}█${NC}"
        sleep 0.05
    done
    echo -e "] ${GREEN}✓${NC}"
}

# Check root
[[ $EUID -ne 0 ]] && error_exit "Must run as root: sudo bash deploy-filebeat-c2.sh"

clear
cat << "BANNER"
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║   ██████╗ ███████╗██████╗ ███████╗██╗     ██╗  ██╗                      ║
║   ██╔══██╗██╔════╝██╔══██╗██╔════╝██║     ██║ ██╔╝                      ║
║   ██████╔╝█████╗  ██║  ██║█████╗  ██║     █████╔╝                       ║
║   ██╔══██╗██╔══╝  ██║  ██║██╔══╝  ██║     ██╔═██╗                       ║
║   ██║  ██║███████╗██████╔╝███████╗███████╗██║  ██╗                      ║
║   ╚═╝  ╚═╝╚══════╝╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝                      ║
║                                                                           ║
║              Filebeat Agent Deployment - Cobalt Strike C2                 ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

BANNER

echo -e "${CYAN}Starting deployment...${NC}"
echo ""

# Check if we're in the correct directory
if [[ ! -d "filebeat" ]] || [[ ! -f "filebeat/filebeat-cobaltstrike.yml" ]]; then
    log_error "Filebeat config not found in current directory"
    log_info "Please extract c2servers.tgz and run from c2package/ directory"
    log_info "Example: tar xzf c2servers.tgz && cd c2package && sudo bash deploy-filebeat-c2.sh"
    exit 1
fi

echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                    PHASE 1: CLEANUP PREVIOUS INSTALLATION                 ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Stop filebeat service
if systemctl is-active --quiet filebeat 2>/dev/null; then
    echo -ne "${CYAN}Stopping filebeat service...${NC} "
    systemctl stop filebeat 2>/dev/null || true
    systemctl disable filebeat 2>/dev/null || true
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${BLUE}ℹ${NC} No running filebeat service found"
fi

# Backup existing config
if [[ -f /etc/filebeat/filebeat.yml ]]; then
    BACKUP_FILE="/etc/filebeat/filebeat.yml.backup.$(date +%s)"
    echo -ne "${CYAN}Backing up existing config...${NC} "
    cp /etc/filebeat/filebeat.yml "$BACKUP_FILE" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} ${YELLOW}(saved to ${BACKUP_FILE})${NC}"
fi

# Remove old registry (forces re-scan of log files)
if [[ -d /var/lib/filebeat/registry ]]; then
    echo -ne "${CYAN}Removing old registry...${NC} "
    rm -rf /var/lib/filebeat/registry 2>/dev/null || true
    echo -e "${GREEN}✓${NC} ${YELLOW}(will re-scan all logs)${NC}"
fi

# Clean old logs
if [[ -d /var/log/filebeat ]] && [[ -n "$(ls -A /var/log/filebeat 2>/dev/null)" ]]; then
    echo -ne "${CYAN}Cleaning old filebeat logs...${NC} "
    rm -rf /var/log/filebeat/* 2>/dev/null || true
    echo -e "${GREEN}✓${NC}"
fi

# Remove old data
if [[ -d /var/lib/filebeat/data ]]; then
    echo -ne "${CYAN}Removing old filebeat data...${NC} "
    rm -rf /var/lib/filebeat/data 2>/dev/null || true
    echo -e "${GREEN}✓${NC}"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                    PHASE 2: INSTALL FILEBEAT                              ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Detect architecture
ARCH="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"
DEB="filebeat-8.15.3-${ARCH}.deb"
FILEBEAT_URL="https://artifacts.elastic.co/downloads/beats/filebeat/${DEB}"

if ! command -v filebeat &>/dev/null; then
    log_info "Downloading Filebeat 8.15.3 for ${ARCH}..."
    progress 20 "Downloading"
    
    if ! curl -fsSL -O "$FILEBEAT_URL" 2>/dev/null; then
        log_error "Download failed - trying alternative method..."
        wget -q "$FILEBEAT_URL" || error_exit "Failed to download Filebeat"
    fi
    
    echo -ne "${CYAN}Installing Filebeat package...${NC} "
    dpkg -i "${DEB}" >/dev/null 2>&1 || apt-get -y -qq install "./${DEB}" >/dev/null 2>&1
    rm -f "${DEB}"
    echo -e "${GREEN}✓${NC}"
    log_success "Filebeat 8.15.3 installed"
else
    INSTALLED_VER=$(filebeat version | grep -oP '\d+\.\d+\.\d+' | head -1)
    log_success "Filebeat already installed (version: ${INSTALLED_VER})"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                    PHASE 3: CONFIGURE FILEBEAT                            ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Detect Cobalt Strike installation
log_info "Detecting Cobalt Strike installation..."

CS_PATH=""
for potential_path in \
    "/opt/cobaltstrike" \
    "/opt/cobaltstrike/cobaltstrike" \
    "$HOME/cobaltstrike" \
    "$HOME/cobaltstrike_3/cobaltstrike/cobaltstrike" \
    "/home/*/cobaltstrike"
do
    if [[ -d "$potential_path" ]]; then
        CS_PATH="$potential_path"
        break
    fi
done

if [[ -z "$CS_PATH" ]]; then
    log_warn "Cobalt Strike auto-detection failed"
    echo -ne "${YELLOW}Enter Cobalt Strike path:${NC} "
    read -r CS_PATH
    [[ ! -d "$CS_PATH" ]] && error_exit "Directory not found: $CS_PATH"
fi

log_success "Cobalt Strike found: ${CYAN}$CS_PATH${NC}"

# Verify log directory exists or will be created
if [[ -d "$CS_PATH/logs" ]]; then
    LOG_DIR="$CS_PATH/logs"
    log_success "Log directory exists: $LOG_DIR"
elif [[ -d "$CS_PATH/server/logs" ]]; then
    LOG_DIR="$CS_PATH/server/logs"
    log_success "Log directory exists: $LOG_DIR"
else
    log_warn "Log directory not found - will be created when teamserver starts"
    LOG_DIR="$CS_PATH/logs"
fi

# Deploy configuration
echo -ne "${CYAN}Deploying RedELK configuration...${NC} "
cp filebeat/filebeat-cobaltstrike.yml /etc/filebeat/filebeat.yml
echo -e "${GREEN}✓${NC}"

# Update paths for actual CS installation
echo -ne "${CYAN}Updating log paths...${NC} "
if [[ -d "$CS_PATH/logs" ]]; then
    sed -i "s|/opt/cobaltstrike/logs|$CS_PATH/logs|g" /etc/filebeat/filebeat.yml
elif [[ -d "$CS_PATH/server/logs" ]]; then
    sed -i "s|/opt/cobaltstrike/logs|$CS_PATH/server/logs|g" /etc/filebeat/filebeat.yml
fi
echo -e "${GREEN}✓${NC}"

# Install certificates
if [[ -f "redelkCA.crt" ]]; then
    echo -ne "${CYAN}Installing CA certificate...${NC} "
    mkdir -p /etc/filebeat/certs
    cp redelkCA.crt /etc/filebeat/certs/
    chmod 644 /etc/filebeat/certs/redelkCA.crt
    echo -e "${GREEN}✓${NC}"
fi

if [[ -f "sshkey" ]]; then
    echo -ne "${CYAN}Installing SSH key...${NC} "
    mkdir -p /etc/filebeat/certs
    cp sshkey /etc/filebeat/certs/
    chmod 600 /etc/filebeat/certs/sshkey
    echo -e "${GREEN}✓${NC}"
fi

# Set permissions
echo -ne "${CYAN}Setting file permissions...${NC} "
chmod 600 /etc/filebeat/filebeat.yml
chown root:root /etc/filebeat/filebeat.yml
echo -e "${GREEN}✓${NC}"

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                    PHASE 4: VALIDATION & TESTING                          ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Test configuration
log_info "Testing Filebeat configuration..."
if filebeat test config -c /etc/filebeat/filebeat.yml 2>&1 | grep -q "Config OK"; then
    log_success "Configuration syntax is valid"
else
    log_error "Configuration test failed!"
    filebeat test config -c /etc/filebeat/filebeat.yml
    error_exit "Fix configuration errors before continuing"
fi

# Test output connectivity
log_info "Testing connection to RedELK server..."
if timeout 10 filebeat test output -c /etc/filebeat/filebeat.yml 2>&1 | grep -q "successfully"; then
    log_success "Connection to RedELK server verified"
else
    log_warn "Cannot reach RedELK server - check network/firewall (port 5044)"
    log_info "Filebeat will auto-retry connections when service starts"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                    PHASE 5: START SERVICE                                 ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Enable service
echo -ne "${CYAN}Enabling filebeat service...${NC} "
systemctl enable filebeat >/dev/null 2>&1
echo -e "${GREEN}✓${NC}"

# Start service
echo -ne "${CYAN}Starting filebeat service...${NC} "
systemctl restart filebeat
sleep 2
echo -e "${GREEN}✓${NC}"

# Verify service is running
if systemctl is-active --quiet filebeat; then
    log_success "Filebeat service is running"
else
    log_error "Filebeat failed to start!"
    echo ""
    log_info "Viewing recent logs:"
    journalctl -u filebeat --no-pager -n 30
    exit 1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                    DEPLOYMENT SUCCESSFUL                                  ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo ""

log_success "Filebeat is now shipping Cobalt Strike logs to RedELK"
echo ""

echo -e "${BOLD}Monitored Log Paths:${NC}"
echo -e "  ${CYAN}•${NC} ${LOG_DIR}/*/beacon_*.log ${YELLOW}(beacon activity)${NC}"
echo -e "  ${CYAN}•${NC} ${LOG_DIR}/*/events.log ${YELLOW}(operator join/leave)${NC}"
echo -e "  ${CYAN}•${NC} ${LOG_DIR}/*/weblog.log ${YELLOW}(web requests)${NC}"
echo -e "  ${CYAN}•${NC} ${LOG_DIR}/*/downloads.log ${YELLOW}(file downloads)${NC}"
echo -e "  ${CYAN}•${NC} ${LOG_DIR}/*/keystrokes.log ${YELLOW}(keystroke logs)${NC}"
echo -e "  ${CYAN}•${NC} ${LOG_DIR}/*/screenshots.log ${YELLOW}(screenshot captures)${NC}"
echo ""

echo -e "${BOLD}Field Structure:${NC} ${GREEN}NESTED${NC} ${YELLOW}(Compatible with RedELK v3.0.6+)${NC}"
echo -e "  ${CYAN}•${NC} infra.log.type: rtops"
echo -e "  ${CYAN}•${NC} c2.program: cobaltstrike"
echo -e "  ${CYAN}•${NC} c2.log.type: beacon/events/weblog/etc"
echo ""

echo -e "${BOLD}Verification Commands:${NC}"
echo -e "  ${CYAN}•${NC} systemctl status filebeat"
echo -e "  ${CYAN}•${NC} journalctl -u filebeat -f ${YELLOW}(follow logs)${NC}"
echo -e "  ${CYAN}•${NC} filebeat test config"
echo -e "  ${CYAN}•${NC} filebeat test output"
echo ""

echo -e "${BOLD}RedELK Dashboard:${NC}"
echo -e "  ${CYAN}•${NC} Wait 2-3 minutes for data to appear"
echo -e "  ${CYAN}•${NC} Check Kibana for ${MAGENTA}rtops-*${NC} index"
echo -e "  ${CYAN}•${NC} View dashboards at ${MAGENTA}Analytics → Dashboards${NC}"
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

