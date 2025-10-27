#!/bin/bash
# HOTFIX: Fix Logstash field references for official RedELK Filebeat configs
# This updates the Logstash parser to use nested field structure ([infra][log][type])
# instead of flat fields ([fields][logtype])

set -euo pipefail

echo "=========================================="
echo "RedELK Logstash Field Structure Hotfix"
echo "=========================================="
echo ""

# Check if running on RedELK server
if [[ ! -f "/opt/RedELK/elkserver/logstash/conf.d/50-filter-c2-cobaltstrike.conf" ]]; then
    echo "[ERROR] This script must be run on the RedELK server"
    echo "[ERROR] Logstash config not found at expected location"
    exit 1
fi

echo "[INFO] Backing up current Logstash config..."
cp /opt/RedELK/elkserver/logstash/conf.d/50-filter-c2-cobaltstrike.conf \
   /opt/RedELK/elkserver/logstash/conf.d/50-filter-c2-cobaltstrike.conf.backup

echo "[INFO] Updating field references..."

# Update main filter condition
sed -i 's/\[fields\]\[logtype\]/[infra][log][type]/g' \
    /opt/RedELK/elkserver/logstash/conf.d/50-filter-c2-cobaltstrike.conf

sed -i 's/\[fields\]\[c2_program\]/[c2][program]/g' \
    /opt/RedELK/elkserver/logstash/conf.d/50-filter-c2-cobaltstrike.conf

sed -i 's/\[fields\]\[c2_log_type\]/[c2][log][type]/g' \
    /opt/RedELK/elkserver/logstash/conf.d/50-filter-c2-cobaltstrike.conf

echo "[INFO] Restarting Logstash container..."
cd /opt/RedELK/elkserver/docker
docker compose restart logstash

echo ""
echo "[INFO] Waiting for Logstash to restart (30 seconds)..."
sleep 30

# Check if Logstash is running
if docker logs redelk-logstash 2>&1 | tail -20 | grep -q "Starting server on port: 5044"; then
    echo "[SUCCESS] Logstash restarted successfully!"
else
    echo "[WARNING] Logstash may still be starting. Check logs with:"
    echo "  docker logs redelk-logstash"
fi

echo ""
echo "=========================================="
echo "Hotfix Applied Successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Wait 2-3 minutes for new logs to be parsed"
echo "2. Check Kibana dashboards (refresh browser)"
echo "3. Verify parsed data:"
echo "   curl -u elastic:RedElk2024Secure 'http://127.0.0.1:9200/rtops-*/_search?size=1&sort=@timestamp:desc' | grep 'beacon.id\\|event.action'"
echo ""
echo "If dashboards still show no data, check:"
echo "- Filebeat is running on C2 server: sudo systemctl status filebeat"
echo "- Filebeat can connect: sudo journalctl -u filebeat -n 50"
echo "- Logs are being generated in Cobalt Strike"
echo ""
