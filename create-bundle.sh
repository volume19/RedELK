#!/bin/bash
# Create deployment bundle for RedELK v3

echo "Creating RedELK v3 deployment bundle..."

# Create temporary directory
BUNDLE_DIR="DEPLOYMENT-BUNDLE"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# Copy all required files
echo "Copying files..."

# Main deployment script
cp redelk_ubuntu_deploy.sh "$BUNDLE_DIR/" 2>/dev/null

# Elasticsearch templates
cp elkserver/elasticsearch/index-templates/*.json "$BUNDLE_DIR/" 2>/dev/null

# Logstash configs
cp elkserver/logstash/conf.d/*.conf "$BUNDLE_DIR/" 2>/dev/null

# Threat feeds
cp elkserver/logstash/threat-feeds/*.txt "$BUNDLE_DIR/" 2>/dev/null

# Kibana dashboards
cp elkserver/kibana/dashboards/*.ndjson "$BUNDLE_DIR/" 2>/dev/null

# Helper scripts
cp scripts/*.sh "$BUNDLE_DIR/" 2>/dev/null

# Filebeat configs
cp c2servers/*.yml "$BUNDLE_DIR/" 2>/dev/null
cp redirs/*.yml "$BUNDLE_DIR/" 2>/dev/null

# Create wrapper script that extracts and runs
cat > "$BUNDLE_DIR/install-redelk.sh" << 'EOF'
#!/bin/bash
# RedELK v3 Auto-Installer
# This script is self-contained when bundled with the tar.gz

set -euo pipefail

echo "================================================"
echo "     RedELK v3.0 Auto-Installer"
echo "================================================"
echo ""

# Check if we're running from inside the extracted bundle
if [[ ! -f "redelk_ubuntu_deploy.sh" ]]; then
    echo "[ERROR] Required files not found. Please extract the full bundle first."
    echo "Usage: tar xzf redelk-v3-deployment.tar.gz && cd DEPLOYMENT-BUNDLE && sudo bash install-redelk.sh"
    exit 1
fi

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Must run as root: sudo bash install-redelk.sh"
    exit 1
fi

echo "[INFO] All files present. Starting deployment..."
echo ""

# Run the main deployment script
bash redelk_ubuntu_deploy.sh

echo ""
echo "================================================"
echo "Installation complete! Check above for details."
echo "================================================"
EOF

chmod +x "$BUNDLE_DIR/install-redelk.sh"

# Create the tarball
tar czf redelk-v3-deployment.tar.gz "$BUNDLE_DIR/"
rm -rf "$BUNDLE_DIR"

echo "Bundle created: redelk-v3-deployment.tar.gz"
echo ""
echo "To deploy:"
echo "  1. Copy to server: scp redelk-v3-deployment.tar.gz user@server:/tmp/"
echo "  2. Extract: tar xzf redelk-v3-deployment.tar.gz"
echo "  3. Deploy: cd DEPLOYMENT-BUNDLE && sudo bash install-redelk.sh"