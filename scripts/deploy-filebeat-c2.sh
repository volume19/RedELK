#!/bin/bash
#############################################################################
# RedELK Filebeat Deployment Script - Cobalt Strike C2 Server
# Purpose: Install and configure filebeat on Cobalt Strike teamserver
# Usage: sudo bash deploy-filebeat-c2.sh
#############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }

error_exit() {
    log_error "$1"
    exit 1
}

# Check root
[[ $EUID -ne 0 ]] && error_exit "Must run as root"

cat << "BANNER"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     RedELK Filebeat Deployment - Cobalt Strike C2        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

BANNER

# Check if we're in the redelk package directory
if [[ ! -f "filebeat/filebeat-cobaltstrike.yml" ]]; then
    log_warn "filebeat-cobaltstrike.yml not found in current directory"
    log_info "Looking for extracted c2servers package..."
    
    if [[ -d "/tmp/c2package/filebeat" ]]; then
        cd /tmp/c2package
        log_success "Found extracted package in /tmp"
    elif [[ -f "$HOME/c2servers.tgz" ]]; then
        log_info "Extracting c2servers.tgz..."
        mkdir -p /tmp/c2package
        tar xzf "$HOME/c2servers.tgz" -C /tmp
        cd /tmp/c2package
    else
        error_exit "Cannot find c2servers package. Please extract c2servers.tgz first."
    fi
fi

# Get Cobalt Strike installation path
log_info "Detecting Cobalt Strike installation..."
CS_PATH=""

if [[ -d "/opt/cobaltstrike" ]]; then
    CS_PATH="/opt/cobaltstrike"
elif [[ -d "$HOME/cobaltstrike" ]]; then
    CS_PATH="$HOME/cobaltstrike"
elif [[ -d "$HOME/cobaltstrike_3/cobaltstrike/cobaltstrike" ]]; then
    CS_PATH="$HOME/cobaltstrike_3/cobaltstrike/cobaltstrike"
else
    read -p "Cobalt Strike installation path: " CS_PATH
    [[ ! -d "$CS_PATH" ]] && error_exit "Cobalt Strike directory not found"
fi

log_success "Cobalt Strike found: $CS_PATH"

# Verify logs directory
if [[ ! -d "$CS_PATH/logs" ]] && [[ ! -d "$CS_PATH/server/logs" ]]; then
    log_warn "Logs directory not found - it will be created when teamserver starts"
fi

# Install filebeat
log_info "Installing filebeat..."
if ! command -v filebeat &>/dev/null; then
    curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.15.3-amd64.deb
    dpkg -i filebeat-8.15.3-amd64.deb
    rm -f filebeat-8.15.3-amd64.deb
    log_success "Filebeat installed"
else
    log_success "Filebeat already installed"
fi

# Stop filebeat
systemctl stop filebeat 2>/dev/null || true

# Backup existing config
if [[ -f /etc/filebeat/filebeat.yml ]]; then
    cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.backup.$(date +%s)
    log_info "Backed up existing config"
fi

# Copy RedELK filebeat config
log_info "Installing RedELK filebeat configuration..."
cp filebeat/filebeat-cobaltstrike.yml /etc/filebeat/filebeat.yml

# Update paths for actual Cobalt Strike installation
log_info "Updating log paths for Cobalt Strike installation..."
if [[ -d "$CS_PATH/logs" ]]; then
    # Logs in main directory
    sed -i "s|/opt/cobaltstrike/logs|$CS_PATH/logs|g" /etc/filebeat/filebeat.yml
elif [[ -d "$CS_PATH/server/logs" ]]; then
    # Logs in server subdirectory
    sed -i "s|/opt/cobaltstrike/logs|$CS_PATH/server/logs|g" /etc/filebeat/filebeat.yml
fi

# Copy CA certificate if exists
if [[ -f "redelkCA.crt" ]]; then
    mkdir -p /etc/filebeat/certs
    cp redelkCA.crt /etc/filebeat/certs/
    chmod 644 /etc/filebeat/certs/redelkCA.crt
    log_success "CA certificate installed"
fi

# Copy SSH key if exists
if [[ -f "sshkey" ]]; then
    mkdir -p /etc/filebeat/certs
    cp sshkey /etc/filebeat/certs/
    chmod 600 /etc/filebeat/certs/sshkey
    log_success "SSH key installed"
fi

# Set proper permissions
chmod 600 /etc/filebeat/filebeat.yml
chown root:root /etc/filebeat/filebeat.yml

# Test configuration
log_info "Testing filebeat configuration..."
if filebeat test config -c /etc/filebeat/filebeat.yml; then
    log_success "Configuration valid"
else
    error_exit "Configuration test failed - check /etc/filebeat/filebeat.yml"
fi

# Test output connectivity
log_info "Testing connection to RedELK server..."
if filebeat test output -c /etc/filebeat/filebeat.yml; then
    log_success "Connection to RedELK server successful"
else
    log_warn "Cannot connect to RedELK server - check network/firewall"
    log_info "Filebeat will retry connections automatically"
fi

# Enable and start filebeat
log_info "Starting filebeat service..."
systemctl enable filebeat
systemctl restart filebeat

# Wait and check status
sleep 3
if systemctl is-active filebeat &>/dev/null; then
    log_success "Filebeat service running"
else
    log_error "Filebeat service failed to start"
    journalctl -u filebeat --no-pager -n 20
    exit 1
fi

# Display status
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║             FILEBEAT DEPLOYMENT COMPLETE                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
log_success "Filebeat is now shipping Cobalt Strike logs to RedELK"
echo ""
log_info "Log paths monitored:"
echo "  • $CS_PATH/logs/*/beacon_*.log"
echo "  • $CS_PATH/logs/*/events.log"
echo "  • $CS_PATH/logs/*/weblog.log"
echo "  • $CS_PATH/logs/*/downloads.log"
echo "  • $CS_PATH/logs/*/keystrokes.log"
echo "  • $CS_PATH/logs/*/screenshots.log"
echo ""
log_info "Verification:"
echo "  • Check status: systemctl status filebeat"
echo "  • View logs: journalctl -u filebeat -f"
echo "  • Test config: filebeat test config"
echo "  • Test output: filebeat test output"
echo ""
log_info "RedELK Dashboard:"
echo "  • Wait 2-3 minutes for logs to appear"
echo "  • Check Kibana for rtops-* index"
echo ""

