#!/usr/bin/env bash
# RedELK Cleanup Script - Clean all RedELK artifacts before fresh install

set -euo pipefail

echo "RedELK Complete Cleanup Script"
echo "=============================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo "[1/10] Stopping all RedELK containers..."
cd /opt/RedELK/elkserver/docker 2>/dev/null && docker compose down -v 2>/dev/null || true
cd /opt/RedELK/elkserver/docker 2>/dev/null && docker-compose down -v 2>/dev/null || true

echo "[2/10] Removing all RedELK containers..."
docker rm -f redelk-elasticsearch redelk-kibana redelk-logstash redelk-nginx 2>/dev/null || true

echo "[3/10] Removing RedELK Docker network..."
docker network rm redelk_redelk 2>/dev/null || true
docker network rm redelk 2>/dev/null || true

echo "[4/10] Removing Docker volumes..."
docker volume rm redelk_esdata 2>/dev/null || true
docker volume rm redelk_es_data 2>/dev/null || true
docker volume ls | grep redelk | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true

echo "[5/10] Removing RedELK directory..."
rm -rf /opt/RedELK

echo "[6/10] Removing systemd services..."
systemctl stop redelk 2>/dev/null || true
systemctl stop redelk-compose 2>/dev/null || true
systemctl disable redelk 2>/dev/null || true
systemctl disable redelk-compose 2>/dev/null || true
rm -f /etc/systemd/system/redelk.service
rm -f /etc/systemd/system/redelk-compose.service
systemctl daemon-reload

echo "[7/10] Removing sysctl configurations..."
rm -f /etc/sysctl.d/99-elastic.conf
rm -f /etc/sysctl.d/99-elasticsearch.conf
sysctl -w vm.max_map_count=65530 >/dev/null 2>&1 || true

echo "[8/10] Cleaning temporary files..."
rm -rf /tmp/redelk*
rm -f /tmp/*.sh

echo "[9/10] Removing log files..."
rm -f /var/log/redelk*.log

echo "[10/10] Pruning unused Docker images..."
docker image prune -f

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "System is ready for fresh RedELK installation."
echo "Next steps:"
echo "  1. Download latest script: curl -o /tmp/install.sh https://raw.githubusercontent.com/volume19/RedELK/master/redelk_ubuntu_deploy.sh"
echo "  2. Run installation: sudo bash /tmp/install.sh"
echo ""