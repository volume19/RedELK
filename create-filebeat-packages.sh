#!/bin/bash
# Create Filebeat Deployment Packages for RedELK
# Run this on your RedELK server to generate c2servers.tgz and redirs.tgz

set -e

echo "Creating RedELK Filebeat deployment packages..."
echo ""

# Get server IP
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)

if [ -z "$SERVER_IP" ]; then
    echo "[ERROR] Could not detect server IP"
    echo "Available interfaces:"
    ip -4 addr show | grep -E "inet\s"
    exit 1
fi

echo "[INFO] RedELK Server IP: $SERVER_IP"
echo ""

# Get script directory (where filebeat configs are)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create working directory
WORK_DIR="/tmp/redelk-packages-$$"
mkdir -p "$WORK_DIR"

#############################################
# C2 SERVERS PACKAGE
#############################################
echo "[INFO] Creating C2 servers package..."

C2_DIR="$WORK_DIR/c2package"
mkdir -p "$C2_DIR/filebeat"

# Copy and update filebeat configs
for config in "$SCRIPT_DIR/c2servers"/*.yml; do
    if [ -f "$config" ]; then
        filename=$(basename "$config")
        sed "s/REDELK_SERVER_IP/${SERVER_IP}/g" "$config" > "$C2_DIR/filebeat/${filename}"
        echo "  - Added $filename with IP: $SERVER_IP"
    fi
done

# Create deployment script for C2
cat > "$C2_DIR/deploy-filebeat.sh" << 'EOFSCRIPT'
#!/bin/bash
set -e

echo "================================================"
echo "  RedELK Filebeat Deployment - C2 Server"
echo "================================================"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Must run as root: sudo bash deploy-filebeat.sh"
    exit 1
fi

# Detect C2 type
if [ -d "/opt/cobaltstrike" ]; then
    C2_TYPE="cobaltstrike"
    CONFIG="filebeat-cobaltstrike.yml"
    echo "[INFO] Detected: Cobalt Strike"
elif [ -d "/opt/PoshC2" ] || [ -d "/var/poshc2" ]; then
    C2_TYPE="poshc2"
    CONFIG="filebeat-poshc2.yml"
    echo "[INFO] Detected: PoshC2"
else
    echo "[WARN] Could not auto-detect C2 type"
    echo ""
    echo "Available configs:"
    ls -1 filebeat/filebeat-*.yml
    echo ""
    read -p "Enter config filename: " CONFIG
    C2_TYPE="manual"
fi

# Check config exists
if [ ! -f "filebeat/$CONFIG" ]; then
    echo "[ERROR] Config not found: filebeat/$CONFIG"
    exit 1
fi

# Install filebeat
echo ""
echo "[INFO] Installing Filebeat..."
if ! command -v filebeat &>/dev/null; then
    curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.15.3-amd64.deb
    dpkg -i filebeat-8.15.3-amd64.deb
    rm -f filebeat-8.15.3-amd64.deb
    echo "[INFO] Filebeat installed"
else
    echo "[INFO] Filebeat already installed"
fi

# Stop filebeat
systemctl stop filebeat 2>/dev/null || true

# Backup existing config
if [ -f /etc/filebeat/filebeat.yml ]; then
    cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.backup.$(date +%s)
    echo "[INFO] Backed up existing config"
fi

# Install new config
cp "filebeat/$CONFIG" /etc/filebeat/filebeat.yml
chmod 600 /etc/filebeat/filebeat.yml
echo "[INFO] Installed $CONFIG"

# Test config
echo ""
echo "[INFO] Testing configuration..."
if ! filebeat test config; then
    echo "[ERROR] Configuration test failed!"
    exit 1
fi
echo "[INFO] Configuration valid"

# Start service
echo ""
echo "[INFO] Starting Filebeat..."
systemctl enable filebeat
systemctl restart filebeat
sleep 3

if systemctl is-active --quiet filebeat; then
    echo "[SUCCESS] Filebeat is running"
else
    echo "[ERROR] Filebeat failed to start"
    echo ""
    echo "Check logs: sudo journalctl -u filebeat -n 50"
    exit 1
fi

echo ""
echo "================================================"
echo "  Deployment Complete!"
echo "================================================"
echo ""
echo "Commands:"
echo "  Status:  systemctl status filebeat"
echo "  Logs:    journalctl -u filebeat -f"
echo "  Restart: systemctl restart filebeat"
echo ""
EOFSCRIPT

chmod +x "$C2_DIR/deploy-filebeat.sh"

# Create README
cat > "$C2_DIR/README.txt" << 'EOFREADME'
RedELK C2 Server Filebeat Deployment
=====================================

QUICK START:
  sudo bash deploy-filebeat.sh

MANUAL DEPLOYMENT:

1. Install Filebeat:
   curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.15.3-amd64.deb
   sudo dpkg -i filebeat-8.15.3-amd64.deb

2. Install config (choose your C2):
   # For Cobalt Strike:
   sudo cp filebeat/filebeat-cobaltstrike.yml /etc/filebeat/filebeat.yml

   # For PoshC2:
   sudo cp filebeat/filebeat-poshc2.yml /etc/filebeat/filebeat.yml

3. Set permissions:
   sudo chmod 600 /etc/filebeat/filebeat.yml

4. Test and start:
   sudo filebeat test config
   sudo systemctl enable filebeat
   sudo systemctl restart filebeat

5. Verify:
   sudo systemctl status filebeat
   sudo journalctl -u filebeat -f

EOFREADME

# Create tarball
tar czf "$WORK_DIR/c2servers.tgz" -C "$WORK_DIR" c2package
echo "[SUCCESS] Created c2servers.tgz"

#############################################
# REDIRECTORS PACKAGE
#############################################
echo ""
echo "[INFO] Creating redirectors package..."

REDIR_DIR="$WORK_DIR/redirpackage"
mkdir -p "$REDIR_DIR/filebeat"

# Copy and update filebeat configs
for config in "$SCRIPT_DIR/redirs"/*.yml; do
    if [ -f "$config" ]; then
        filename=$(basename "$config")
        sed "s/REDELK_SERVER_IP/${SERVER_IP}/g" "$config" > "$REDIR_DIR/filebeat/${filename}"
        echo "  - Added $filename with IP: $SERVER_IP"
    fi
done

# Create deployment script for redirectors
cat > "$REDIR_DIR/deploy-filebeat.sh" << 'EOFSCRIPT'
#!/bin/bash
set -e

echo "================================================"
echo "  RedELK Filebeat Deployment - Redirector"
echo "================================================"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Must run as root: sudo bash deploy-filebeat.sh"
    exit 1
fi

# Auto-detect redirector type
REDIR_TYPE=""
if command -v nginx &>/dev/null && systemctl is-active nginx &>/dev/null; then
    REDIR_TYPE="nginx"
    CONFIG="filebeat-nginx.yml"
    echo "[INFO] Detected: Nginx"
elif command -v apache2 &>/dev/null || command -v httpd &>/dev/null; then
    REDIR_TYPE="apache"
    CONFIG="filebeat-apache.yml"
    echo "[INFO] Detected: Apache"
elif command -v haproxy &>/dev/null && systemctl is-active haproxy &>/dev/null; then
    REDIR_TYPE="haproxy"
    CONFIG="filebeat-haproxy.yml"
    echo "[INFO] Detected: HAProxy"
else
    echo "[WARN] Could not auto-detect redirector type"
    echo ""
    echo "Available configs:"
    ls -1 filebeat/filebeat-*.yml
    echo ""
    read -p "Enter config filename: " CONFIG
    REDIR_TYPE="manual"
fi

# Check config exists
if [ ! -f "filebeat/$CONFIG" ]; then
    echo "[ERROR] Config not found: filebeat/$CONFIG"
    exit 1
fi

# Install filebeat
echo ""
echo "[INFO] Installing Filebeat..."
if ! command -v filebeat &>/dev/null; then
    curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.15.3-amd64.deb
    dpkg -i filebeat-8.15.3-amd64.deb
    rm -f filebeat-8.15.3-amd64.deb
    echo "[INFO] Filebeat installed"
else
    echo "[INFO] Filebeat already installed"
fi

# Stop filebeat
systemctl stop filebeat 2>/dev/null || true

# Backup existing config
if [ -f /etc/filebeat/filebeat.yml ]; then
    cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.backup.$(date +%s)
    echo "[INFO] Backed up existing config"
fi

# Install new config
cp "filebeat/$CONFIG" /etc/filebeat/filebeat.yml
chmod 600 /etc/filebeat/filebeat.yml
echo "[INFO] Installed $CONFIG"

# Test config
echo ""
echo "[INFO] Testing configuration..."
if ! filebeat test config; then
    echo "[ERROR] Configuration test failed!"
    exit 1
fi
echo "[INFO] Configuration valid"

# Start service
echo ""
echo "[INFO] Starting Filebeat..."
systemctl enable filebeat
systemctl restart filebeat
sleep 3

if systemctl is-active --quiet filebeat; then
    echo "[SUCCESS] Filebeat is running"
else
    echo "[ERROR] Filebeat failed to start"
    echo ""
    echo "Check logs: sudo journalctl -u filebeat -n 50"
    exit 1
fi

echo ""
echo "================================================"
echo "  Deployment Complete!"
echo "================================================"
echo ""
echo "Commands:"
echo "  Status:  systemctl status filebeat"
echo "  Logs:    journalctl -u filebeat -f"
echo "  Restart: systemctl restart filebeat"
echo ""
EOFSCRIPT

chmod +x "$REDIR_DIR/deploy-filebeat.sh"

# Create README
cat > "$REDIR_DIR/README.txt" << 'EOFREADME'
RedELK Redirector Filebeat Deployment
======================================

QUICK START:
  sudo bash deploy-filebeat.sh

MANUAL DEPLOYMENT:

1. Install Filebeat:
   curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.15.3-amd64.deb
   sudo dpkg -i filebeat-8.15.3-amd64.deb

2. Install config (choose your redirector):
   # For Nginx:
   sudo cp filebeat/filebeat-nginx.yml /etc/filebeat/filebeat.yml

   # For Apache:
   sudo cp filebeat/filebeat-apache.yml /etc/filebeat/filebeat.yml

   # For HAProxy:
   sudo cp filebeat/filebeat-haproxy.yml /etc/filebeat/filebeat.yml

3. Set permissions:
   sudo chmod 600 /etc/filebeat/filebeat.yml

4. Test and start:
   sudo filebeat test config
   sudo systemctl enable filebeat
   sudo systemctl restart filebeat

5. Verify:
   sudo systemctl status filebeat
   sudo journalctl -u filebeat -f

EOFREADME

# Create tarball
tar czf "$WORK_DIR/redirs.tgz" -C "$WORK_DIR" redirpackage
echo "[SUCCESS] Created redirs.tgz"

# Move to final location
echo ""
echo "[INFO] Moving packages to /opt/RedELK..."
mkdir -p /opt/RedELK
mv "$WORK_DIR/c2servers.tgz" /opt/RedELK/
mv "$WORK_DIR/redirs.tgz" /opt/RedELK/
chmod 644 /opt/RedELK/*.tgz

# Cleanup
rm -rf "$WORK_DIR"

echo ""
echo "========================================"
echo "  PACKAGES CREATED SUCCESSFULLY!"
echo "========================================"
echo ""
echo "Location:"
echo "  /opt/RedELK/c2servers.tgz  (for C2 servers)"
echo "  /opt/RedELK/redirs.tgz     (for redirectors)"
echo ""
echo "Next steps:"
echo "  1. Copy packages to your C2/redirectors:"
echo "     scp /opt/RedELK/c2servers.tgz user@c2-server:/tmp/"
echo "     scp /opt/RedELK/redirs.tgz user@redirector:/tmp/"
echo ""
echo "  2. On C2 server:"
echo "     cd /tmp && tar xzf c2servers.tgz"
echo "     cd c2package && sudo bash deploy-filebeat.sh"
echo ""
echo "  3. On redirector:"
echo "     cd /tmp && tar xzf redirs.tgz"
echo "     cd redirpackage && sudo bash deploy-filebeat.sh"
echo ""
