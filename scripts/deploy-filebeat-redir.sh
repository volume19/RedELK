#!/bin/bash
#############################################################################
# RedELK Filebeat Deployment Script - Redirectors
# Purpose: Install and configure filebeat on nginx redirectors
# Usage: sudo bash deploy-filebeat-redir.sh
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
║     RedELK Filebeat Deployment - Nginx Redirector        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

BANNER

# Check if we're in the redelk package directory
if [[ ! -f "filebeat/filebeat-nginx.yml" ]]; then
    error_exit "filebeat-nginx.yml not found. Extract redirs.tgz first."
fi

# Install filebeat
log_info "Installing filebeat..."
if ! command -v filebeat &>/dev/null; then
    curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.15.3-amd64.deb
    dpkg -i filebeat-8.15.3-amd64.deb
    rm -f filebeat-8.15.3-amd64.deb
fi
log_success "Filebeat installed"

# Stop filebeat
systemctl stop filebeat 2>/dev/null || true

# Backup existing config
if [[ -f /etc/filebeat/filebeat.yml ]]; then
    cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.backup.$(date +%s)
    log_info "Backed up existing config"
fi

# Copy RedELK filebeat config
log_info "Installing RedELK filebeat configuration..."
cp filebeat/filebeat-nginx.yml /etc/filebeat/filebeat.yml

# Copy CA certificate if exists
if [[ -f "redelkCA.crt" ]]; then
    mkdir -p /etc/filebeat/certs
    cp redelkCA.crt /etc/filebeat/certs/
    chmod 644 /etc/filebeat/certs/redelkCA.crt
    log_success "CA certificate installed"
fi

# Set proper permissions
chmod 600 /etc/filebeat/filebeat.yml
chown root:root /etc/filebeat/filebeat.yml

# Test configuration
log_info "Testing filebeat configuration..."
if filebeat test config -c /etc/filebeat/filebeat.yml; then
    log_success "Configuration valid"
else
    error_exit "Configuration test failed"
fi

# Test output connectivity
log_info "Testing connection to RedELK server..."
if filebeat test output -c /etc/filebeat/filebeat.yml; then
    log_success "Connection to RedELK server successful"
else
    log_warn "Cannot connect to RedELK server - check network/firewall"
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
log_success "Filebeat is now shipping nginx logs to RedELK"
echo ""
log_info "Verification:"
echo "  • Check status: systemctl status filebeat"
echo "  • View logs: journalctl -u filebeat -f"
echo "  • Test config: filebeat test config"
echo "  • Test output: filebeat test output"
echo ""
log_info "Logs being shipped:"
echo "  • /var/log/nginx/access.log"
echo "  • /var/log/nginx/error.log"
echo ""

