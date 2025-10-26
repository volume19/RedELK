#!/bin/bash
# RedELK Beacon Manager
# Query and manage beacon information from Elasticsearch

set -euo pipefail

# Configuration
ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ELASTIC_PASSWORD:-changeme}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to query Elasticsearch
es_query() {
    local query=$1
    curl -s -u "$ES_USER:$ES_PASS" \
        -H "Content-Type: application/json" \
        "http://$ES_HOST:$ES_PORT/rtops-*/_search" \
        -d "$query" 2>/dev/null
}

# Function to list active beacons
list_beacons() {
    echo -e "${BLUE}Active Beacons:${NC}"
    echo "----------------------------------------"

    local query='{
      "size": 0,
      "query": {
        "bool": {
          "must": [
            { "exists": { "field": "beacon.id" } },
            { "range": { "@timestamp": { "gte": "now-24h" } } }
          ]
        }
      },
      "aggs": {
        "beacons": {
          "terms": {
            "field": "beacon.id.keyword",
            "size": 1000
          },
          "aggs": {
            "last_seen": {
              "max": { "field": "@timestamp" }
            },
            "hostname": {
              "terms": {
                "field": "beacon.hostname.keyword",
                "size": 1
              }
            },
            "user": {
              "terms": {
                "field": "beacon.user.keyword",
                "size": 1
              }
            },
            "internal_ip": {
              "terms": {
                "field": "beacon.internal_ip",
                "size": 1
              }
            },
            "os": {
              "terms": {
                "field": "beacon.os.keyword",
                "size": 1
              }
            }
          }
        }
      }
    }'

    local response=$(es_query "$query")
    local beacons=$(echo "$response" | jq -r '.aggregations.beacons.buckets[]' 2>/dev/null)

    if [ -z "$beacons" ]; then
        echo -e "${YELLOW}No active beacons found${NC}"
        return
    fi

    echo "$response" | jq -r '.aggregations.beacons.buckets[] |
        "\(.key)\t\(.hostname.buckets[0].key // "N/A")\t\(.user.buckets[0].key // "N/A")\t\(.internal_ip.buckets[0].key // "N/A")\t\(.os.buckets[0].key // "N/A")\t\(.last_seen.value_as_string // "N/A")"' |
    while IFS=$'\t' read -r id hostname user ip os last_seen; do
        # Calculate time since last seen
        if [ "$last_seen" != "N/A" ]; then
            last_epoch=$(date -d "$last_seen" +%s 2>/dev/null || echo "0")
            now_epoch=$(date +%s)
            diff=$((now_epoch - last_epoch))

            if [ $diff -lt 300 ]; then  # Less than 5 minutes
                status="${GREEN}●${NC} Active"
            elif [ $diff -lt 3600 ]; then  # Less than 1 hour
                status="${YELLOW}●${NC} Idle"
            else
                status="${RED}●${NC} Stale"
            fi
        else
            status="${RED}●${NC} Unknown"
        fi

        printf "%s %-12s %-20s %-15s %-15s %s\n" \
            "$status" "$id" "$hostname" "$user" "$ip" "$os"
    done
}

# Function to show beacon details
show_beacon_details() {
    local beacon_id=$1

    echo -e "${BLUE}Beacon Details: $beacon_id${NC}"
    echo "----------------------------------------"

    local query="{
      \"size\": 1,
      \"query\": {
        \"bool\": {
          \"must\": [
            { \"term\": { \"beacon.id.keyword\": \"$beacon_id\" } }
          ]
        }
      },
      \"sort\": [
        { \"@timestamp\": { \"order\": \"desc\" } }
      ]
    }"

    local response=$(es_query "$query")

    if [ "$(echo "$response" | jq -r '.hits.total.value')" -eq 0 ]; then
        echo -e "${RED}Beacon not found${NC}"
        return 1
    fi

    echo "$response" | jq -r '.hits.hits[0]._source |
        "ID: \(.beacon.id // "N/A")
Hostname: \(.beacon.hostname // "N/A")
Username: \(.beacon.user // "N/A")
Process: \(.beacon.process // "N/A") (PID: \(.beacon.pid // "N/A"))
Internal IP: \(.beacon.internal_ip // "N/A")
External IP: \(.beacon.external_ip // "N/A")
OS: \(.beacon.os // "N/A")
Sleep: \(.beacon.sleep // "N/A")s
Jitter: \(.beacon.jitter // "N/A")%
Last Check-in: \(.["@timestamp"] // "N/A")
Note: \(.beacon.note // "None")"'
}

# Function to show beacon commands
show_beacon_commands() {
    local beacon_id=$1
    local limit=${2:-10}

    echo -e "${BLUE}Recent Commands for Beacon: $beacon_id${NC}"
    echo "----------------------------------------"

    local query="{
      \"size\": $limit,
      \"query\": {
        \"bool\": {
          \"must\": [
            { \"term\": { \"beacon.id.keyword\": \"$beacon_id\" } },
            { \"exists\": { \"field\": \"command.type\" } }
          ]
        }
      },
      \"sort\": [
        { \"@timestamp\": { \"order\": \"desc\" } }
      ]
    }"

    local response=$(es_query "$query")

    if [ "$(echo "$response" | jq -r '.hits.total.value')" -eq 0 ]; then
        echo -e "${YELLOW}No commands found for this beacon${NC}"
        return
    fi

    echo "$response" | jq -r '.hits.hits[]._source |
        "[\(.["@timestamp"] // "N/A")] \(.c2.operator // "N/A"): \(.command.type // "N/A") - \(.command.input // "" | .[0:100])"'
}

# Function to search for IOCs
search_iocs() {
    local ioc=$1

    echo -e "${BLUE}Searching for IOC: $ioc${NC}"
    echo "----------------------------------------"

    local query="{
      \"size\": 100,
      \"query\": {
        \"query_string\": {
          \"query\": \"*$ioc*\"
        }
      },
      \"_source\": [\"@timestamp\", \"beacon.id\", \"beacon.hostname\", \"message\"],
      \"sort\": [
        { \"@timestamp\": { \"order\": \"desc\" } }
      ]
    }"

    local response=$(es_query "$query")
    local count=$(echo "$response" | jq -r '.hits.total.value')

    if [ "$count" -eq 0 ]; then
        echo -e "${GREEN}No matches found${NC}"
        return
    fi

    echo -e "${YELLOW}Found $count matches:${NC}"
    echo "$response" | jq -r '.hits.hits[]._source |
        "[\(.["@timestamp"] // "N/A")] Beacon: \(.beacon.id // "N/A") Host: \(.beacon.hostname // "N/A")"' |
    head -20

    if [ "$count" -gt 20 ]; then
        echo -e "${YELLOW}... and $((count - 20)) more${NC}"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "======================================"
    echo "       RedELK Beacon Manager"
    echo "======================================"
    echo "1. List active beacons"
    echo "2. Show beacon details"
    echo "3. Show beacon commands"
    echo "4. Search for IOCs"
    echo "5. Export beacon data"
    echo "0. Exit"
    echo ""
}

# Export beacon data
export_beacon_data() {
    local output_file="redelk_beacons_$(date +%Y%m%d_%H%M%S).json"

    echo -e "${BLUE}Exporting beacon data to $output_file...${NC}"

    local query='{
      "size": 10000,
      "query": {
        "bool": {
          "must": [
            { "exists": { "field": "beacon.id" } }
          ]
        }
      }
    }'

    es_query "$query" | jq '.hits.hits[]._source' > "$output_file"

    local count=$(jq -s 'length' "$output_file")
    echo -e "${GREEN}Exported $count beacon records to $output_file${NC}"
}

# Parse command line arguments
case "${1:-menu}" in
    list)
        list_beacons
        ;;
    details)
        if [ -z "${2:-}" ]; then
            echo -e "${RED}Error: Beacon ID required${NC}"
            echo "Usage: $0 details <beacon_id>"
            exit 1
        fi
        show_beacon_details "$2"
        ;;
    commands)
        if [ -z "${2:-}" ]; then
            echo -e "${RED}Error: Beacon ID required${NC}"
            echo "Usage: $0 commands <beacon_id> [limit]"
            exit 1
        fi
        show_beacon_commands "$2" "${3:-10}"
        ;;
    search)
        if [ -z "${2:-}" ]; then
            echo -e "${RED}Error: IOC required${NC}"
            echo "Usage: $0 search <ioc>"
            exit 1
        fi
        search_iocs "$2"
        ;;
    export)
        export_beacon_data
        ;;
    menu|*)
        while true; do
            show_menu
            read -p "Select option: " option

            case $option in
                1)
                    list_beacons
                    ;;
                2)
                    read -p "Enter beacon ID: " beacon_id
                    show_beacon_details "$beacon_id"
                    ;;
                3)
                    read -p "Enter beacon ID: " beacon_id
                    read -p "Number of commands to show [10]: " limit
                    limit=${limit:-10}
                    show_beacon_commands "$beacon_id" "$limit"
                    ;;
                4)
                    read -p "Enter IOC to search: " ioc
                    search_iocs "$ioc"
                    ;;
                5)
                    export_beacon_data
                    ;;
                0)
                    echo "Exiting..."
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid option${NC}"
                    ;;
            esac

            echo ""
            read -p "Press Enter to continue..."
        done
        ;;
esac