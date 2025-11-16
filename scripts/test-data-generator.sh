#!/bin/bash
# RedELK Test Data Generator
# Generates sample data to test dashboards and verify setup

set -euo pipefail

ITERATIONS=0
SLEEP_SECONDS=2
while (($#)); do
    case "$1" in
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --sleep)
            SLEEP_SECONDS="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

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

ES_HOST="localhost"
ES_PORT="9200"
ES_USER="elastic"
ES_PASS="$(load_elastic_password)"

echo "======================================"
echo "     RedELK Test Data Generator"
echo "======================================"
echo ""
echo "This script will generate sample data to test your dashboards."
echo "Press Ctrl+C to stop generation."
echo ""

# Function to generate random IP
random_ip() {
    echo "$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"
}

# Function to generate random beacon data
generate_beacon_data() {
    local beacon_id="BID-$(uuidgen | cut -c1-8)"
    local hostname="DESKTOP-$(cat /dev/urandom | tr -dc 'A-Z0-9' | fold -w 6 | head -n 1)"
    local user="$(shuf -n 1 -e "admin" "user" "john.doe" "jane.smith" "bob.jones")"
    local internal_ip="192.168.$((RANDOM % 10)).$((RANDOM % 256))"
    local external_ip="$(random_ip)"
    local os="$(shuf -n 1 -e "Windows 10" "Windows 11" "Windows Server 2019")"
    local sleep=$((RANDOM % 300 + 30))

    cat <<EOF
{
    "@timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "infra": {
        "log": {
            "type": "rtops"
        }
    },
    "c2": {
        "program": "cobaltstrike",
        "log": {
            "type": "beacon"
        },
        "operator": "operator1",
        "teamserver": "teamserver.local"
    },
    "beacon": {
        "id": "$beacon_id",
        "hostname": "$hostname",
        "user": "$user",
        "internal_ip": "$internal_ip",
        "external_ip": "$external_ip",
        "os": "$os",
        "sleep": $sleep,
        "process": "explorer.exe",
        "pid": $((RANDOM % 10000 + 1000))
    },
    "message": "Beacon $beacon_id checkin from $hostname"
}
EOF
}

# Function to generate redirector traffic data
generate_redir_data() {
    local source_ip="$(random_ip)"
    local method="$(shuf -n 1 -e "GET" "POST" "GET" "GET")"
    local path="$(shuf -n 1 -e "/" "/api/update" "/config" "/static/js/app.js" "/favicon.ico")"
    local status="$(shuf -n 1 -e "200" "200" "200" "404" "403" "301")"
    local ua="$(shuf -n 1 -e "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" "python-requests/2.28.0" "curl/7.68.0")"

    cat <<EOF
{
    "@timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "infra": {
        "log": {
            "type": "redirtraffic"
        }
    },
    "source": {
        "ip": "$source_ip",
        "port": $((RANDOM % 50000 + 10000))
    },
    "http": {
        "request": {
            "method": "$method",
            "path": "$path"
        },
        "response": {
            "status_code": $status,
            "bytes": $((RANDOM % 10000 + 100))
        }
    },
    "user_agent": {
        "original": "$ua"
    },
    "redir": {
        "program": "apache",
        "name": "redir-01"
    },
    "message": "$source_ip - - [$(date)] \"$method $path HTTP/1.1\" $status"
}
EOF
}

# Function to generate alarm data
generate_alarm_data() {
    local alarm_name="$(shuf -n 1 -e "Sandbox Detection" "TOR Exit Node" "Security Scanner" "Suspicious Activity")"
    local severity="$(shuf -n 1 -e "low" "medium" "high" "critical")"
    local source_ip="$(random_ip)"

    cat <<EOF
{
    "@timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "alarm": {
        "name": "$alarm_name",
        "severity": "$severity",
        "type": "threat",
        "description": "Automated detection triggered for $source_ip"
    },
    "source": {
        "ip": "$source_ip"
    },
    "message": "Alarm: $alarm_name detected from $source_ip"
}
EOF
}

# Send data to Elasticsearch
send_data() {
    local index="$1"
    local data="$2"

    curl -s -X POST "http://$ES_HOST:$ES_PORT/$index/_doc" \
        -u "$ES_USER:$ES_PASS" \
        -H "Content-Type: application/json" \
        -d "$data" >/dev/null
}

# Main loop
echo "[INFO] Starting data generation..."
echo "[INFO] Data will appear in Kibana dashboards within 5-10 seconds"
echo ""

counter=0
while true; do
    send_data "rtops-$(date +%Y.%m.%d)" "$(generate_beacon_data)"
    for i in {1..3}; do
        send_data "redirtraffic-$(date +%Y.%m.%d)" "$(generate_redir_data)"
    done
    if [ $((counter % 10)) -eq 0 ]; then
        send_data "alarms-$(date +%Y.%m.%d)" "$(generate_alarm_data)"
    fi

    counter=$((counter + 1))
    echo -n "."
    if [ $((counter % 10)) -eq 0 ]; then
        echo " Generated $counter batches"
    fi

    if (( ITERATIONS > 0 && counter >= ITERATIONS )); then
        echo "[INFO] Completed ${counter} batches"
        break
    fi

    sleep "$SLEEP_SECONDS"
done
