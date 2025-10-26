#!/bin/bash
# Fix deployment package accessibility
# Run this if packages were created before the accessibility fix

REDELK_PATH="/opt/RedELK"

echo "[INFO] Making deployment packages accessible..."

# Make base directory traversable
chmod 755 "${REDELK_PATH}" 2>/dev/null || true

# Fix permissions on original packages
if [[ -f "${REDELK_PATH}/c2servers.tgz" ]]; then
    chmod 644 "${REDELK_PATH}/c2servers.tgz"
    echo "[INFO] Fixed ${REDELK_PATH}/c2servers.tgz (644)"
fi

if [[ -f "${REDELK_PATH}/redirs.tgz" ]]; then
    chmod 644 "${REDELK_PATH}/redirs.tgz"
    echo "[INFO] Fixed ${REDELK_PATH}/redirs.tgz (644)"
fi

# Copy to /tmp for easy access
if [[ -f "${REDELK_PATH}/c2servers.tgz" ]]; then
    cp "${REDELK_PATH}/c2servers.tgz" /tmp/c2servers.tgz
    chmod 644 /tmp/c2servers.tgz
    echo "[INFO] Copied to /tmp/c2servers.tgz (world-readable)"
fi

if [[ -f "${REDELK_PATH}/redirs.tgz" ]]; then
    cp "${REDELK_PATH}/redirs.tgz" /tmp/redirs.tgz
    chmod 644 /tmp/redirs.tgz
    echo "[INFO] Copied to /tmp/redirs.tgz (world-readable)"
fi

echo ""
echo "[INFO] Deployment packages are now accessible:"
echo "  /tmp/c2servers.tgz"
echo "  /tmp/redirs.tgz"
echo ""
echo "Download with:"
echo "  scp user@redelk-server:/tmp/c2servers.tgz ."
echo "  scp user@redelk-server:/tmp/redirs.tgz ."
