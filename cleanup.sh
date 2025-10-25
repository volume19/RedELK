#!/bin/bash
# RedELK Complete Cleanup

echo "Cleaning up RedELK..."

# Stop containers
cd /opt/RedELK/elkserver/docker 2>/dev/null && docker compose down -v 2>/dev/null || true

# Remove containers
docker rm -f redelk-elasticsearch redelk-kibana redelk-logstash redelk-nginx 2>/dev/null || true

# Remove network
docker network rm redelk_redelk 2>/dev/null || true

# Remove volumes
docker volume rm $(docker volume ls -q | grep redelk) 2>/dev/null || true

# Remove files
rm -rf /opt/RedELK
rm -f /etc/systemd/system/redelk.service
rm -f /etc/sysctl.d/99-elasticsearch.conf
rm -f /var/log/redelk*.log

# Reset kernel
sysctl -w vm.max_map_count=65530 >/dev/null 2>&1 || true

# Reload systemd
systemctl daemon-reload

echo "✅ Cleanup complete!"