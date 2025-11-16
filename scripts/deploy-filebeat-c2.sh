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
readonly BACKUP_ROOT="/var/backups/redelk-filebeat"
readonly CLEAN_INSTALL_MODE="${PRESERVE_EXISTING:-0}"

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }

backup_and_remove() {
    local path="$1"
    local label="$2"
    if [[ -e "$path" ]]; then
        mkdir -p "$BACKUP_ROOT"
        local stamp archive copy_dest
        stamp=$(date +%Y%m%d%H%M%S)
        archive="${BACKUP_ROOT}/${label}-${stamp}.tgz"
        if tar -czf "$archive" -C "$(dirname "$path")" "$(basename "$path")" >/dev/null 2>&1; then
            log_info "Archived ${label} to ${archive}"
        else
            copy_dest="${BACKUP_ROOT}/${label}-${stamp}"
            cp -a "$path" "$copy_dest"
            log_warn "Tar backup failed; copied to ${copy_dest} instead"
            archive="$copy_dest"
        fi
        rm -rf "$path"
        log_success "Removed ${path}"
    fi
}

wipe_previous_installation() {
    if [[ "$CLEAN_INSTALL_MODE" == "1" ]]; then
        log_warn "PRESERVE_EXISTING=1 set - skipping cleanup and keeping current Filebeat configuration"
        return
    fi

    log_info "Preferred clean install path selected - wiping prior Filebeat deployment"

    if systemctl list-unit-files | grep -q "^filebeat\.service"; then
        echo -ne "${CYAN}Stopping and disabling old filebeat service...${NC} "
        systemctl stop filebeat 2>/dev/null || true
        systemctl disable filebeat 2>/dev/null || true
        systemctl reset-failed filebeat 2>/dev/null || true
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${BLUE}ℹ${NC} No existing systemd unit found"
    fi

    if dpkg -s filebeat >/dev/null 2>&1; then
        echo -ne "${CYAN}Purging previous Filebeat package...${NC} "
        DEBIAN_FRONTEND=noninteractive apt-get purge -y filebeat >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true
        echo -e "${GREEN}✓${NC}"
    fi

    backup_and_remove "/etc/filebeat" "etc-filebeat"

    if [[ -d /var/lib/filebeat ]]; then
        echo -ne "${CYAN}Removing /var/lib/filebeat...${NC} "
        rm -rf /var/lib/filebeat 2>/dev/null || true
        echo -e "${GREEN}✓${NC}"
    fi

    if [[ -d /var/log/filebeat ]]; then
        echo -ne "${CYAN}Removing /var/log/filebeat...${NC} "
        rm -rf /var/log/filebeat 2>/dev/null || true
        echo -e "${GREEN}✓${NC}"
    fi

    if [[ -d /etc/systemd/system/filebeat.service.d ]]; then
        echo -ne "${CYAN}Removing systemd overrides...${NC} "
        rm -rf /etc/systemd/system/filebeat.service.d 2>/dev/null || true
        echo -e "${GREEN}✓${NC}"
    fi

    systemctl daemon-reload 2>/dev/null || true
    log_success "Previous Filebeat configuration removed (set PRESERVE_EXISTING=1 to skip in future runs)"
}

error_exit() {
    log_error "$1"
    exit 1
}

prompt_redelk_host() {
    local host="${REDELK_HOST:-}"
    if [[ -n "$host" ]]; then
        printf '%s' "$host"
        return
    fi

    while [[ -z "$host" ]]; do
        echo -ne "${CYAN}Enter RedELK collector hostname or IP:${NC} "
        read -r host
        [[ -z "$host" ]] && log_warn "Collector address is required"
    done

    printf '%s' "$host"
}

choose_ca_certificate() {
    local candidate
    if [[ -n "${REDELK_CA_CERT:-}" ]]; then
        candidate="${REDELK_CA_CERT}"
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
        log_warn "REDELK_CA_CERT set but file not found: $candidate"
    fi

    for candidate in redelkCA.crt elkserver.crt "certs/elkserver.crt"; do
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    while true; do
        echo -ne "${CYAN}Path to RedELK TLS certificate (elkserver.crt):${NC} "
        read -r candidate
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
        log_error "Certificate not found at $candidate"
    done
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

wipe_previous_installation

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

# Configure Logstash endpoint
LOGSTASH_HOST="$(prompt_redelk_host)"
log_success "Using RedELK collector: ${CYAN}${LOGSTASH_HOST}${NC}"
sed -i "s|REDELK_HOST|${LOGSTASH_HOST}|g" /etc/filebeat/filebeat.yml

# Install certificates
CA_SOURCE="$(choose_ca_certificate)"
echo -ne "${CYAN}Installing CA certificate from ${CA_SOURCE}...${NC} "
mkdir -p /etc/filebeat/certs
cp "${CA_SOURCE}" /etc/filebeat/certs/redelk-ca.crt
chmod 644 /etc/filebeat/certs/redelk-ca.crt
echo -e "${GREEN}✓${NC}"

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

