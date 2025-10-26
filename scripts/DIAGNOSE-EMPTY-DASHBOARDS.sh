#!/bin/bash
# Diagnose why RedELK dashboards are empty

echo "=========================================="
echo "RedELK Dashboard Diagnostic"
echo "=========================================="
echo ""

# Check 1: What's in Elasticsearch?
echo "[1] Checking Elasticsearch indices..."
curl -s -u elastic:RedElk2024Secure "http://localhost:9200/_cat/indices/rtops-*,redirtraffic-*?v&s=index"
echo ""

# Check 2: How many documents?
echo "[2] Checking document counts..."
RTOPS_COUNT=$(curl -s -u elastic:RedElk2024Secure "http://localhost:9200/rtops-*/_count" | jq -r '.count // 0')
REDIR_COUNT=$(curl -s -u elastic:RedElk2024Secure "http://localhost:9200/redirtraffic-*/_count" | jq -r '.count // 0')
echo "rtops-* documents: $RTOPS_COUNT"
echo "redirtraffic-* documents: $REDIR_COUNT"
echo ""

# Check 3: Sample the data
echo "[3] Sample data from rtops-*:"
curl -s -u elastic:RedElk2024Secure "http://localhost:9200/rtops-*/_search?size=3&pretty" | jq '.hits.hits[]._source | {logtype, infralogtype, message: .message[0:100]}'
echo ""

# Check 4: Are there actual log files on Polaris?
echo "[4] Checking for C2 log files on remote server..."
echo "Run this on POLARIS:"
echo "  find /opt -name 'beacon_*.log' -o -name 'events.log' 2>/dev/null | head -10"
echo "  ls -lh /opt/cobaltstrike/logs/ 2>/dev/null"
echo ""

# Check 5: What's Filebeat actually reading?
echo "[5] Check Filebeat registry (shows what files it's reading)..."
echo "Run this on POLARIS:"
echo "  sudo cat /var/lib/filebeat/registry/filebeat/log.json | jq '.[] | {source, offset}' | head -20"
echo ""

# Check 6: Check Kibana index patterns
echo "[6] Checking Kibana index patterns..."
curl -s -u elastic:RedElk2024Secure "http://localhost:5601/api/saved_objects/_find?type=index-pattern" \
  -H "kbn-xsrf: true" | jq -r '.saved_objects[] | {id: .id, title: .attributes.title}'
echo ""

# Check 7: Logstash pipeline stats
echo "[7] Checking Logstash pipeline stats..."
curl -s http://localhost:9600/_node/stats/pipelines?pretty | jq '.pipelines.main.events'
echo ""

echo "=========================================="
echo "NEXT STEPS:"
echo "=========================================="
echo ""
echo "If rtops document count is 0 or very low:"
echo "  1. Verify Cobalt Strike is actually running and creating logs on Polaris"
echo "  2. Check the paths in /etc/filebeat/filebeat.yml on Polaris match actual log locations"
echo "  3. Generate test data: sudo /opt/RedELK/scripts/test-data-generator.sh"
echo ""
echo "If documents exist but dashboards are empty:"
echo "  1. In Kibana, go to Analytics > Discover"
echo "  2. Select index pattern: rtops-*"
echo "  3. Set time range to 'Last 24 hours'"
echo "  4. Check if you see any documents"
echo "  5. If yes, the dashboards may need field mapping fixes"
echo ""
