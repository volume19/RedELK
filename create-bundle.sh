#!/bin/bash
# Create deployment bundle for RedELK v3

echo "Creating RedELK v3 deployment bundle..."

# Create temporary directory
BUNDLE_DIR="DEPLOYMENT-BUNDLE"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# Copy all required files
echo "Copying files..."

# Main deployment script (REQUIRED)
if [[ -f "redelk_ubuntu_deploy.sh" ]]; then
    # CRITICAL: Convert CRLF to LF before bundling
    sed 's/\r$//' redelk_ubuntu_deploy.sh > "$BUNDLE_DIR/redelk_ubuntu_deploy.sh"
    echo "  ✓ Deployment script (line endings fixed)"
else
    echo "  ✗ Missing redelk_ubuntu_deploy.sh"
fi

# Elasticsearch templates
if ls elkserver/elasticsearch/index-templates/*.json >/dev/null 2>&1; then
    cp elkserver/elasticsearch/index-templates/*.json "$BUNDLE_DIR/" 2>/dev/null
    echo "  ✓ Elasticsearch templates"
fi

# Logstash configs
if ls elkserver/logstash/conf.d/*.conf >/dev/null 2>&1; then
    cp elkserver/logstash/conf.d/*.conf "$BUNDLE_DIR/" 2>/dev/null
    echo "  ✓ Logstash configs"
fi

# Threat feeds
if ls elkserver/logstash/threat-feeds/*.txt >/dev/null 2>&1; then
    cp elkserver/logstash/threat-feeds/*.txt "$BUNDLE_DIR/" 2>/dev/null
    echo "  ✓ Threat feeds"
fi

# Kibana dashboards
if ls elkserver/kibana/dashboards/*.ndjson >/dev/null 2>&1; then
    cp elkserver/kibana/dashboards/*.ndjson "$BUNDLE_DIR/" 2>/dev/null
    echo "  ✓ Kibana dashboards"
fi

# Helper scripts
if ls scripts/*.sh >/dev/null 2>&1; then
    for script in scripts/*.sh; do
        sed 's/\r$//' "$script" > "$BUNDLE_DIR/$(basename "$script")"
    done
    echo "  ✓ Helper scripts (line endings fixed)"
fi

# Filebeat configs for C2 servers
if ls c2servers/*.yml >/dev/null 2>&1; then
    cp c2servers/*.yml "$BUNDLE_DIR/" 2>/dev/null
    COUNT=$(ls c2servers/*.yml 2>/dev/null | wc -l)
    echo "  ✓ C2 filebeat configs ($COUNT files)"
else
    echo "  ⚠ No C2 filebeat configs (will be auto-generated)"
fi

# Filebeat configs for redirectors
if ls redirs/*.yml >/dev/null 2>&1; then
    cp redirs/*.yml "$BUNDLE_DIR/" 2>/dev/null
    COUNT=$(ls redirs/*.yml 2>/dev/null | wc -l)
    echo "  ✓ Redirector filebeat configs ($COUNT files)"
else
    echo "  ⚠ No redirector filebeat configs (will be auto-generated)"
fi

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
BUNDLE_SIZE=$(du -h redelk-v3-deployment.tar.gz | cut -f1)
rm -rf "$BUNDLE_DIR"

echo ""
echo "=========================================="
echo "Bundle created successfully!"
echo "=========================================="
echo ""
echo "File: redelk-v3-deployment.tar.gz ($BUNDLE_SIZE)"
echo ""
echo "DEPLOYMENT INSTRUCTIONS:"
echo ""
echo "1. Copy to server:"
echo "   scp redelk-v3-deployment.tar.gz root@YOUR_SERVER:/tmp/"
echo ""
echo "2. On server, extract and deploy:"
echo "   cd /tmp"
echo "   tar xzf redelk-v3-deployment.tar.gz"
echo "   cd DEPLOYMENT-BUNDLE"
echo "   sudo bash install-redelk.sh"
echo ""
echo "3. After deployment, packages will be at:"
echo "   /tmp/c2servers.tgz"
echo "   /tmp/redirs.tgz"
echo ""
echo "=========================================="