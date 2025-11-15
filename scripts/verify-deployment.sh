#!/bin/bash
# RedELK Deployment Verification Script
# Comprehensive checks to ensure all components are properly deployed

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
readonly REDELK_PATH="/opt/RedELK"
readonly ES_USER="elastic"
readonly ES_PASS="${ELASTIC_PASSWORD:-RedElk2024Secure}"

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Verification functions
check() {
    local description=$1
    local command=$2
    local expected=${3:-}

    echo -n "Checking: $description... "

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} PASS"
        ((CHECKS_PASSED++))
        return 0
    else
        if [ -n "$expected" ] && [ "$expected" == "warn" ]; then
            echo -e "${YELLOW}⚠${NC} WARNING"
            ((CHECKS_WARNING++))
            return 1
        else
            echo -e "${RED}✗${NC} FAIL"
            ((CHECKS_FAILED++))
            return 1
        fi
    fi
}

check_file() {
    local description=$1
    local filepath=$2

    echo -n "Checking file: $description... "

    if [ -f "$filepath" ]; then
        echo -e "${GREEN}✓${NC} EXISTS"
        ((CHECKS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} MISSING"
        ((CHECKS_FAILED++))
        return 1
    fi
}

check_dir() {
    local description=$1
    local dirpath=$2

    echo -n "Checking directory: $description... "

    if [ -d "$dirpath" ]; then
        local count=$(ls -1 "$dirpath" 2>/dev/null | wc -l)
        echo -e "${GREEN}✓${NC} EXISTS ($count items)"
        ((CHECKS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} MISSING"
        ((CHECKS_FAILED++))
        return 1
    fi
}

check_service() {
    local name=$1
    local port=$2

    echo -n "Checking service: $name on port $port... "

    if nc -z localhost "$port" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} RUNNING"
        ((CHECKS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} NOT RUNNING"
        ((CHECKS_FAILED++))
        return 1
    fi
}

check_container() {
    local name=$1

    echo -n "Checking container: $name... "

    local status=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")
    local health=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo "none")

    if [ "$status" == "running" ]; then
        if [ "$health" == "healthy" ] || [ "$health" == "none" ]; then
            echo -e "${GREEN}✓${NC} RUNNING (health: $health)"
            ((CHECKS_PASSED++))
            return 0
        else
            echo -e "${YELLOW}⚠${NC} RUNNING but $health"
            ((CHECKS_WARNING++))
            return 1
        fi
    else
        echo -e "${RED}✗${NC} $status"
        ((CHECKS_FAILED++))
        return 1
    fi
}

check_es_index_template() {
    local template=$1

    echo -n "Checking ES template: $template... "

    local exists=$(curl -s -u "$ES_USER:$ES_PASS" \
        "http://localhost:9200/_index_template/$template" 2>/dev/null | \
        grep -c '"name"' || echo "0")

    if [ "$exists" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} EXISTS"
        ((CHECKS_PASSED++))
        return 0
    else
        echo -e "${YELLOW}⚠${NC} NOT FOUND"
        ((CHECKS_WARNING++))
        return 1
    fi
}

# Main verification
main() {
    echo "======================================"
    echo "     RedELK Deployment Verification"
    echo "======================================"
    echo ""

    echo -e "${BLUE}1. Docker Containers:${NC}"
    echo "---------------------"
    check_container "redelk-elasticsearch"
    check_container "redelk-kibana"
    check_container "redelk-logstash"
    check_container "redelk-nginx"
    echo ""

    echo -e "${BLUE}2. Network Services:${NC}"
    echo "--------------------"
    check_service "Elasticsearch" 9200
    check_service "Kibana" 5601
    check_service "Logstash Beats" 5044
    check_service "HTTP" 80
    check_service "HTTPS" 443
    echo ""

    echo -e "${BLUE}3. Directory Structure:${NC}"
    echo "-----------------------"
    check_dir "RedELK base" "$REDELK_PATH"
    check_dir "ELK stack root" "$REDELK_PATH/elkserver"
    check_dir "Certificates" "$REDELK_PATH/certs"
    check_dir "Logstash configs" "$REDELK_PATH/elkserver/logstash/conf.d"
    check_dir "Logstash pipelines" "$REDELK_PATH/elkserver/logstash/pipelines"
    check_dir "Index templates" "$REDELK_PATH/elkserver/elasticsearch/index-templates"
    check_dir "Kibana dashboards" "$REDELK_PATH/elkserver/kibana/dashboards"
    check_dir "Threat feeds" "$REDELK_PATH/elkserver/logstash/threat-feeds"
    check_dir "Helper scripts" "$REDELK_PATH/scripts"
    check_dir "C2 Filebeat configs" "$REDELK_PATH/c2servers"
    check_dir "Redirector Filebeat configs" "$REDELK_PATH/redirs"
    check_dir "Nginx config dir" "$REDELK_PATH/elkserver/nginx"
    check_dir "Kibana config dir" "$REDELK_PATH/elkserver/config"
    echo ""

    echo -e "${BLUE}4. Configuration Files:${NC}"
    echo "-----------------------"
    check_file "Docker Compose" "$REDELK_PATH/elkserver/docker-compose.yml"
    check_file "Compose environment" "$REDELK_PATH/elkserver/.env"
    check_file "Logstash settings" "$REDELK_PATH/elkserver/logstash/logstash.yml"
    check_file "Logstash pipelines.yml" "$REDELK_PATH/elkserver/logstash/pipelines.yml"
    check_file "Kibana config" "$REDELK_PATH/elkserver/config/kibana.yml"
    check_file "Nginx config" "$REDELK_PATH/elkserver/nginx/kibana.conf"
    check_file "Nginx htpasswd" "$REDELK_PATH/elkserver/nginx/htpasswd"
    check_file "Server certificate" "$REDELK_PATH/certs/elkserver.crt"
    check_file "Server key" "$REDELK_PATH/certs/elkserver.key"
    echo ""

    echo -e "${BLUE}5. Helper Scripts:${NC}"
    echo "------------------"
    check_file "Health check script" "$REDELK_PATH/scripts/redelk-health-check.sh"
    check_file "Beacon manager script" "$REDELK_PATH/scripts/redelk-beacon-manager.sh"
    check_file "Threat feed updater" "$REDELK_PATH/scripts/update-threat-feeds.sh"
    check_file "Deployment verifier" "$REDELK_PATH/scripts/verify-deployment.sh"
    check_file "C2 Filebeat deployer" "$REDELK_PATH/scripts/deploy-filebeat-c2.sh"
    check_file "Redirector Filebeat deployer" "$REDELK_PATH/scripts/deploy-filebeat-redir.sh"
    check_file "Test data generator" "$REDELK_PATH/scripts/test-data-generator.sh"
    check_file "Data checker" "$REDELK_PATH/scripts/check-redelk-data.sh"
    check_file "Kibana dashboard export" "$REDELK_PATH/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson"
    check_file "CDN threat feed" "$REDELK_PATH/elkserver/logstash/threat-feeds/cdn-ip-lists.txt"
    check_file "TOR threat feed" "$REDELK_PATH/elkserver/logstash/threat-feeds/tor-exit-nodes.txt"
    echo ""

    echo -e "${BLUE}6. Elasticsearch Components:${NC}"
    echo "----------------------------"
    check_es_index_template "rtops"
    check_es_index_template "redirtraffic"
    check_es_index_template "alarms"

    # Check cluster health
    echo -n "Checking ES cluster health... "
    local health=$(curl -s -u "$ES_USER:$ES_PASS" \
        "http://localhost:9200/_cluster/health" 2>/dev/null | \
        jq -r '.status' 2>/dev/null || echo "unknown")

    case "$health" in
        green)
            echo -e "${GREEN}✓${NC} GREEN"
            ((CHECKS_PASSED++))
            ;;
        yellow)
            echo -e "${YELLOW}⚠${NC} YELLOW"
            ((CHECKS_WARNING++))
            ;;
        *)
            echo -e "${RED}✗${NC} $health"
            ((CHECKS_FAILED++))
            ;;
    esac
    echo ""

    echo -e "${BLUE}7. Logstash Components:${NC}"
    echo "-----------------------"
    check_file "Input config" "$REDELK_PATH/elkserver/logstash/conf.d/10-input-filebeat.conf"
    check_file "Apache parser" "$REDELK_PATH/elkserver/logstash/conf.d/20-filter-redir-apache.conf"
    check_file "Nginx parser" "$REDELK_PATH/elkserver/logstash/conf.d/21-filter-redir-nginx.conf"
    check_file "HAProxy parser" "$REDELK_PATH/elkserver/logstash/conf.d/22-filter-redir-haproxy.conf"
    check_file "Cobalt Strike parser" "$REDELK_PATH/elkserver/logstash/conf.d/50-filter-c2-cobaltstrike.conf"
    check_file "PoshC2 parser" "$REDELK_PATH/elkserver/logstash/conf.d/51-filter-c2-poshc2.conf"
    check_file "GeoIP enrichment" "$REDELK_PATH/elkserver/logstash/conf.d/60-enrich-geoip.conf"
    check_file "CDN detection" "$REDELK_PATH/elkserver/logstash/conf.d/61-enrich-cdn.conf"
    check_file "User agent parser" "$REDELK_PATH/elkserver/logstash/conf.d/62-enrich-useragent.conf"
    check_file "Threat detection" "$REDELK_PATH/elkserver/logstash/conf.d/70-detection-threats.conf"
    check_file "Output config" "$REDELK_PATH/elkserver/logstash/conf.d/90-outputs.conf"
    echo ""

    echo -e "${BLUE}8. Filebeat Templates:${NC}"
    echo "----------------------"
    check_file "Cobalt Strike template" "$REDELK_PATH/c2servers/filebeat-cobaltstrike.yml"
    check_file "PoshC2 template" "$REDELK_PATH/c2servers/filebeat-poshc2.yml"
    check_file "Apache template" "$REDELK_PATH/redirs/filebeat-apache.yml"
    check_file "Nginx template" "$REDELK_PATH/redirs/filebeat-nginx.yml"
    check_file "HAProxy template" "$REDELK_PATH/redirs/filebeat-haproxy.yml"
    echo ""

    echo -e "${BLUE}9. System Requirements:${NC}"
    echo "------------------------"
    echo -n "Checking vm.max_map_count... "
    local map_count=$(sysctl -n vm.max_map_count 2>/dev/null)
    if [ "$map_count" -ge 262144 ]; then
        echo -e "${GREEN}✓${NC} $map_count"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}✗${NC} $map_count (should be >= 262144)"
        ((CHECKS_FAILED++))
    fi

    echo -n "Checking disk space... "
    local disk_usage=$(df -h /var/lib/docker 2>/dev/null | awk 'NR==2 {gsub("%",""); print $5}')
    if [ "$disk_usage" -lt 80 ]; then
        echo -e "${GREEN}✓${NC} ${disk_usage}% used"
        ((CHECKS_PASSED++))
    elif [ "$disk_usage" -lt 90 ]; then
        echo -e "${YELLOW}⚠${NC} ${disk_usage}% used"
        ((CHECKS_WARNING++))
    else
        echo -e "${RED}✗${NC} ${disk_usage}% used"
        ((CHECKS_FAILED++))
    fi

    echo -n "Checking available memory... "
    local mem_avail=$(free -m | awk 'NR==2 {print $7}')
    if [ "$mem_avail" -gt 2048 ]; then
        echo -e "${GREEN}✓${NC} ${mem_avail}MB available"
        ((CHECKS_PASSED++))
    elif [ "$mem_avail" -gt 1024 ]; then
        echo -e "${YELLOW}⚠${NC} ${mem_avail}MB available"
        ((CHECKS_WARNING++))
    else
        echo -e "${RED}✗${NC} ${mem_avail}MB available"
        ((CHECKS_FAILED++))
    fi

    echo -n "Checking cron job... "
    if crontab -l 2>/dev/null | grep -q "update-threat-feeds.sh"; then
        echo -e "${GREEN}✓${NC} Threat feed updater scheduled"
        ((CHECKS_PASSED++))
    else
        echo -e "${YELLOW}⚠${NC} Threat feed updater not scheduled"
        ((CHECKS_WARNING++))
    fi
    echo ""

    # Summary
    echo "======================================"
    echo "            Summary"
    echo "======================================"
    echo -e "${GREEN}Passed:${NC}   $CHECKS_PASSED"
    echo -e "${YELLOW}Warnings:${NC} $CHECKS_WARNING"
    echo -e "${RED}Failed:${NC}   $CHECKS_FAILED"
    echo ""

    if [ "$CHECKS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✓ RedELK deployment verification PASSED${NC}"
        echo ""
        echo "All critical components are properly deployed and running."
        return 0
    elif [ "$CHECKS_FAILED" -le 3 ]; then
        echo -e "${YELLOW}⚠ RedELK deployment has minor issues${NC}"
        echo ""
        echo "Most components are working but some issues need attention."
        return 1
    else
        echo -e "${RED}✗ RedELK deployment has significant issues${NC}"
        echo ""
        echo "Please review the failed checks and fix the issues."
        return 2
    fi
}

# Run verification
main "$@"