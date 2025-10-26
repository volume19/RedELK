#!/bin/bash
# Emergency Dashboard Import Fix for RedELK
set -e

echo "=== RedELK Dashboard Import Fix ==="
echo ""

# Check if dashboard file exists
if [[ ! -f /opt/RedELK/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson ]]; then
    echo "[ERROR] Dashboard file not found!"
    echo "[INFO] Checking what files exist..."
    ls -la /opt/RedELK/elkserver/kibana/dashboards/ || echo "Directory doesn't exist"
    exit 1
fi

echo "[INFO] Dashboard file exists: $(ls -lh /opt/RedELK/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson)"
echo ""

# Check Kibana is accessible
echo "[INFO] Testing Kibana API..."
if ! curl -sf http://127.0.0.1:5601/api/status >/dev/null; then
    echo "[ERROR] Kibana is not accessible"
    exit 1
fi
echo "[INFO] Kibana API is responding"
echo ""

# Create index patterns first
echo "[INFO] Creating index patterns..."
for pattern in "rtops-*" "redirtraffic-*" "alarms-*"; do
    pattern_id="${pattern/\*/}"
    echo "  Creating: $pattern"
    curl -X POST "http://127.0.0.1:5601/api/saved_objects/index-pattern/${pattern_id}" \
        -u "elastic:RedElk2024Secure" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{\"attributes\":{\"title\":\"${pattern}\",\"timeFieldName\":\"@timestamp\"}}" 2>&1 | \
        grep -q "\"id\"" && echo "  ✓ Created" || echo "  ✓ Already exists"
done
echo ""

# Import dashboards
echo "[INFO] Importing RedELK dashboards..."
response=$(curl -X POST "http://127.0.0.1:5601/api/saved_objects/_import?overwrite=true" \
    -u "elastic:RedElk2024Secure" \
    -H "kbn-xsrf: true" \
    -F "file=@/opt/RedELK/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson" 2>&1)

echo "$response" | jq '.' 2>/dev/null || echo "$response"
echo ""

if echo "$response" | grep -q '"success":true'; then
    echo "[SUCCESS] Dashboards imported successfully!"
    echo ""
    echo "Access them at: https://$(hostname -I | awk '{print $1}')/app/dashboards"
else
    echo "[ERROR] Dashboard import failed. Response above shows the error."
    echo ""
    echo "Common issues:"
    echo "  1. Kibana not fully initialized - wait 2 minutes and try again"
    echo "  2. Old Elasticsearch data - indices may need to be deleted"
    echo "  3. Dashboard file format incompatible with Kibana version"
    exit 1
fi

# Set default index pattern
echo "[INFO] Setting default index pattern to rtops-*..."
curl -X POST "http://127.0.0.1:5601/api/kibana/settings" \
    -u "elastic:RedElk2024Secure" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d '{"changes":{"defaultIndex":"rtops-*"}}' >/dev/null 2>&1 || true

echo ""
echo "=== Complete ==="
