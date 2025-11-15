#!/bin/bash
# RedELK Health Check Script
# Monitors all RedELK components and reports status

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
readonly ENV_FILE="${SCRIPT_DIR}/../elkserver/.env"

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

readonly ES_PASS="$(load_elastic_password)"
FAILURES=0
WARNINGS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "       RedELK Health Check"
echo "======================================"
echo ""

# Function to check service status
check_service() {
    local service=$1
    local port=$2
    local name=$3

    echo -n "Checking $name... "

    if nc -z localhost "$port" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Running on port $port"
        return 0
    else
        echo -e "${RED}✗${NC} Not responding on port $port"
        ((FAILURES++))
        return 1
    fi
}

# Function to check Docker container
check_container() {
    local container=$1
    local name=$2

    echo -n "Checking $name container... "

    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container.*Up.*healthy"; then
        echo -e "${GREEN}✓${NC} Healthy"
        return 0
    elif docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container.*Up"; then
        echo -e "${YELLOW}⚠${NC} Running but not healthy"
        ((WARNINGS++))
        return 1
    else
        echo -e "${RED}✗${NC} Not running or unhealthy"
        ((FAILURES++))
        return 1
    fi
}

# Check Docker containers
echo "Docker Containers:"
echo "------------------"
check_container "redelk-elasticsearch" "Elasticsearch"
check_container "redelk-logstash" "Logstash"
check_container "redelk-kibana" "Kibana"
echo ""

# Check services
echo "Services:"
echo "---------"
check_service "elasticsearch" 9200 "Elasticsearch API"
check_service "kibana" 5601 "Kibana UI"
check_service "logstash" 5044 "Logstash Beats"
echo ""

# Check Elasticsearch cluster health
echo "Elasticsearch Cluster:"
echo "---------------------"
ES_HEALTH=$(curl -s -u "elastic:${ES_PASS}" http://localhost:9200/_cluster/health 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown")

case "$ES_HEALTH" in
    "green")
        echo -e "Cluster Status: ${GREEN}$ES_HEALTH${NC}"
        ;;
    "yellow")
        echo -e "Cluster Status: ${YELLOW}$ES_HEALTH${NC}"
        ;;
    "red"|"unknown")
        echo -e "Cluster Status: ${RED}$ES_HEALTH${NC}"
        ;;
esac

# Check indices
echo ""
echo "Indices:"
echo "--------"
for index in "rtops-*" "redirtraffic-*" "alarms-*"; do
    COUNT=$(curl -s -u "elastic:${ES_PASS}" "http://localhost:9200/${index}/_count" 2>/dev/null | jq -r '.count' 2>/dev/null || echo "0")
    if [ "$COUNT" != "0" ]; then
        echo -e "$index: ${GREEN}$COUNT documents${NC}"
    else
        echo -e "$index: ${YELLOW}No documents${NC}"
    fi
done

# Check Filebeat agents
echo ""
echo "Filebeat Agents:"
echo "---------------"
BEATS=$(curl -s -u "elastic:${ES_PASS}" "http://localhost:9200/.monitoring-beats-*/_search?size=0" -H 'Content-Type: application/json' -d '
{
  "aggs": {
    "beats": {
      "terms": {
        "field": "beats_stats.beat.name.keyword",
        "size": 100
      }
    }
  }
}' 2>/dev/null | jq -r '.aggregations.beats.buckets[].key' 2>/dev/null)

if [ -z "$BEATS" ]; then
    echo -e "${YELLOW}No Filebeat agents connected${NC}"
    ((WARNINGS++))
else
    echo "$BEATS" | while read -r beat; do
        echo -e "${GREEN}✓${NC} $beat"
    done
fi

# Check disk space
echo ""
echo "Disk Space:"
echo "-----------"
DISK_USAGE=$(df -h /var/lib/docker 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "Docker storage: ${GREEN}${DISK_USAGE}% used${NC}"
elif [ "$DISK_USAGE" -lt 90 ]; then
    echo -e "Docker storage: ${YELLOW}${DISK_USAGE}% used${NC}"
    ((WARNINGS++))
else
    echo -e "Docker storage: ${RED}${DISK_USAGE}% used${NC}"
    ((FAILURES++))
fi

echo ""
echo "Warnings: $WARNINGS"
echo "Failures: $FAILURES"
echo "======================================"
echo "Health check complete"
echo "======================================"

if [ "$FAILURES" -gt 0 ]; then
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    exit 2
fi
