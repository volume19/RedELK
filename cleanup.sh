#!/bin/bash
# RedELK Complete Cleanup

set -e

echo "RedELK Complete Cleanup"
echo "======================"

# Check root
if [[ $EUID -ne 0 ]]; then
   echo "Run as root"
   exit 1
fi

echo "[1/8] Stopping containers..."
cd /opt/RedELK/elkserver/docker 2>/dev/null && docker compose down -v 2>/dev/null || true

echo "[2/8] Removing containers..."
docker rm -f redelk-elasticsearch redelk-kibana redelk-logstash redelk-nginx 2>/dev/null || true

echo "[3/8] Removing networks..."
docker network rm redelk_redelk redelk 2>/dev/null || true

echo "[4/8] Removing volumes..."
docker volume ls -q | grep redelk | xargs -r docker volume rm 2>/dev/null || true

echo "[5/8] Removing files..."
rm -rf /opt/RedELK
rm -f /etc/systemd/system/redelk.service
rm -f /etc/sysctl.d/99-elasticsearch.conf
rm -f /var/log/redelk*.log
rm -f /tmp/redelk* /tmp/install.sh /tmp/cleanup.sh

echo "[6/8] Resetting kernel..."
sysctl -w vm.max_map_count=65530 >/dev/null 2>&1 || true

echo "[7/8] Reloading systemd..."
systemctl daemon-reload

echo "[8/8] Pruning Docker..."
docker system prune -f >/dev/null 2>&1 || true

echo ""
echo "✅ Cleanup complete!"
echo "Ready for fresh install."