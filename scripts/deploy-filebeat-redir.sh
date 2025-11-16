#!/bin/bash
#############################################################################
# RedELK Filebeat Deployment Script - Redirectors (ENHANCED)
# Purpose: Install and configure filebeat on redirector servers
# Features: Complete cleanup, nested field structure, visual feedback
# Usage: sudo bash deploy-filebeat-redir.sh
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
        log_warn "PRESERVE_EXISTING=1 set - keeping current Filebeat configuration"
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
[[ $EUID -ne 0 ]] && error_exit "Must run as root: sudo bash deploy-filebeat-redir.sh"

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
║              Filebeat Agent Deployment - Redirector                       ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

BANNER

echo -e "${CYAN}Starting deployment...${NC}"
echo ""

# Check if we're in the correct directory
if [[ ! -d "filebeat" ]]; then
    log_error "Filebeat config directory not found"
    log_info "Please extract redirs.tgz and run from redirpackage/ directory"
    log_info "Example: tar xzf redirs.tgz && cd redirpackage && sudo bash deploy-filebeat-redir.sh"
    exit 1
fi

# Detect redirector type
REDIR_TYPE=""
CONFIG_FILE=""

if [[ -f "filebeat/filebeat-nginx.yml" ]] && command -v nginx &>/dev/null; then
    REDIR_TYPE="nginx"
    CONFIG_FILE="filebeat/filebeat-nginx.yml"
elif [[ -f "filebeat/filebeat-apache.yml" ]] && (command -v apache2 &>/dev/null || command -v httpd &>/dev/null); then
    REDIR_TYPE="apache"
    CONFIG_FILE="filebeat/filebeat-apache.yml"
elif [[ -f "filebeat/filebeat-haproxy.yml" ]] && command -v haproxy &>/dev/null; then
    REDIR_TYPE="haproxy"
    CONFIG_FILE="filebeat/filebeat-haproxy.yml"
elif [[ -f "filebeat/filebeat-nginx.yml" ]]; then
    REDIR_TYPE="nginx"
    CONFIG_FILE="filebeat/filebeat-nginx.yml"
    log_warn "Nginx not detected, but using nginx config anyway"
elif [[ -f "filebeat/filebeat-apache.yml" ]]; then
    REDIR_TYPE="apache"
    CONFIG_FILE="filebeat/filebeat-apache.yml"
    log_warn "Apache not detected, but using apache config anyway"
else
    error_exit "No suitable filebeat config found in filebeat/ directory"
fi

log_success "Redirector type: ${MAGENTA}${REDIR_TYPE}${NC}"

echo ""
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

# Deploy configuration
echo -ne "${CYAN}Deploying RedELK configuration...${NC} "
cp "$CONFIG_FILE" /etc/filebeat/filebeat.yml
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

log_success "Filebeat is now shipping ${REDIR_TYPE} logs to RedELK"
echo ""

echo -e "${BOLD}Monitored Log Paths (${REDIR_TYPE}):${NC}"
case "$REDIR_TYPE" in
    nginx)
        echo -e "  ${CYAN}•${NC} /var/log/nginx/access.log ${YELLOW}(HTTP requests)${NC}"
        echo -e "  ${CYAN}•${NC} /var/log/nginx/error.log ${YELLOW}(errors)${NC}"
        ;;
    apache)
        echo -e "  ${CYAN}•${NC} /var/log/apache2/access.log ${YELLOW}(HTTP requests)${NC}"
        echo -e "  ${CYAN}•${NC} /var/log/apache2/ssl_access.log ${YELLOW}(HTTPS requests)${NC}"
        echo -e "  ${CYAN}•${NC} /var/log/httpd/access_log ${YELLOW}(alternate path)${NC}"
        ;;
    haproxy)
        echo -e "  ${CYAN}•${NC} /var/log/haproxy.log ${YELLOW}(proxy traffic)${NC}"
        ;;
esac
echo ""

echo -e "${BOLD}Field Structure:${NC} ${GREEN}NESTED${NC} ${YELLOW}(Compatible with RedELK v3.0.6+)${NC}"
echo -e "  ${CYAN}•${NC} infra.log.type: redirtraffic"
echo -e "  ${CYAN}•${NC} redir.program: ${REDIR_TYPE}"
echo ""

echo -e "${BOLD}Verification Commands:${NC}"
echo -e "  ${CYAN}•${NC} systemctl status filebeat"
echo -e "  ${CYAN}•${NC} journalctl -u filebeat -f ${YELLOW}(follow logs)${NC}"
echo -e "  ${CYAN}•${NC} filebeat test config"
echo -e "  ${CYAN}•${NC} filebeat test output"
echo ""

echo -e "${BOLD}RedELK Dashboard:${NC}"
echo -e "  ${CYAN}•${NC} Wait 2-3 minutes for data to appear"
echo -e "  ${CYAN}•${NC} Check Kibana for ${MAGENTA}redirtraffic-*${NC} index"
echo -e "  ${CYAN}•${NC} View dashboards at ${MAGENTA}Analytics → Dashboards${NC}"
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

