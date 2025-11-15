#!/bin/bash
# Check if RedELK is receiving data

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/../elkserver/.env"

load_elastic_password() {
    if [[ -n "${ELASTIC_PASSWORD:-}" ]]; then
        printf '%s' "${ELASTIC_PASSWORD}"
        return 0
    fi

    if [[ -f "${ENV_FILE}" ]]; then
        local value=""
        while IFS='=' read -r key val; do
            if [[ "${key}" == "ELASTIC_PASSWORD" ]]; then
                value=${val%$'\r'}
            fi
        done <"${ENV_FILE}"

        if [[ -n "${value}" ]]; then
            printf '%s' "${value}"
            return 0
        fi
    fi

    printf '%s' "RedElk2024Secure"
}

ELASTIC_PASSWORD="$(load_elastic_password)"

echo "=========================================="
echo "RedELK Data Flow Diagnostics"
echo "=========================================="
echo ""

echo "[1] Checking Elasticsearch indices..."
curl -s -u "elastic:${ELASTIC_PASSWORD}" http://127.0.0.1:9200/_cat/indices/*ops-*,*traffic-*,*alarm*?v=true&s=index || echo "ERROR: Cannot connect to Elasticsearch"
echo ""

echo "[2] Checking document counts..."
echo "rtops index (beacon/C2 data):"
curl -s -u "elastic:${ELASTIC_PASSWORD}" http://127.0.0.1:9200/rtops-*/_count | grep -o '"count":[0-9]*'
echo ""

echo "redirtraffic index (redirector data):"
curl -s -u "elastic:${ELASTIC_PASSWORD}" http://127.0.0.1:9200/redirtraffic-*/_count | grep -o '"count":[0-9]*'
echo ""

echo "[3] Checking recent documents in rtops..."
curl -s -u "elastic:${ELASTIC_PASSWORD}" -H 'Content-Type: application/json' \
  http://127.0.0.1:9200/rtops-*/_search?size=1 -d '{"sort":[{"@timestamp":{"order":"desc"}}],"_source":["@timestamp","beacon.*","command.*","c2.*"]}' | grep -o '"took":[0-9]*\|"hits":{"total":{"value":[0-9]*\|"_source":{[^}]*}'
echo ""

echo "[4] Checking Filebeat connections to Logstash..."
echo "Logstash should be listening on port 5044:"
if ss -tunlp 2>/dev/null | grep -q 5044; then
    ss -tunlp 2>/dev/null | grep 5044
elif command -v netstat >/dev/null 2>&1; then
    netstat -tunlp 2>/dev/null | grep 5044 || echo "No listener found on 5044"
else
    echo "netstat/ss unavailable - unable to verify port 5044"
fi
echo ""

echo "[5] Check Logstash recent logs for Filebeat connections..."
docker logs --tail=50 redelk-logstash 2>&1 | grep -i "beats\|connection\|client"
echo ""

echo "=========================================="
echo "Troubleshooting Steps:"
echo "=========================================="
echo "1. If indices exist but count=0, check Filebeat on C2 server"
echo "2. On C2 server run: sudo systemctl status filebeat"
echo "3. On C2 server check logs: sudo journalctl -u filebeat -n 50"
echo "4. On C2 server test connection: sudo filebeat test output"
echo "5. Verify Cobalt Strike logs exist and are readable"
echo "6. Check logs are at one of these paths:"
echo "   - /opt/cobaltstrike/logs/*/beacon_*.log"
echo "   - /opt/cobaltstrike/server/logs/*/beacon_*.log"
echo "   - /home/*/cobaltstrike/*/server/logs/*/beacon_*.log"
echo ""

