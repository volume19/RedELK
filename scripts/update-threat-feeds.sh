#!/bin/bash
# RedELK Threat Feed Updater
# Updates various threat intelligence feeds used by RedELK

set -euo pipefail

# Configuration
readonly FEED_DIR="/opt/RedELK/elkserver/logstash/threat-feeds"
readonly LOG_FILE="/var/log/redelk_feed_update.log"
readonly TEMP_DIR="/tmp/redelk_feeds_$$"

# Create temp directory
mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Update TOR exit nodes
update_tor_nodes() {
    log "Updating TOR exit node list..."
    local tor_url="https://check.torproject.org/exit-addresses"
    local tor_file="${FEED_DIR}/tor-exit-nodes.txt"

    if curl -sS "$tor_url" -o "${TEMP_DIR}/tor_raw.txt" 2>/dev/null; then
        echo "# TOR Exit Node IPs - Updated $(date)" > "${TEMP_DIR}/tor-exit-nodes.txt"
        echo "# Format: IP,\"true\"" >> "${TEMP_DIR}/tor-exit-nodes.txt"

        grep "^ExitAddress" "${TEMP_DIR}/tor_raw.txt" | \
            awk '{print $2 ",\"true\""}' >> "${TEMP_DIR}/tor-exit-nodes.txt"

        if [ -s "${TEMP_DIR}/tor-exit-nodes.txt" ]; then
            mv "${TEMP_DIR}/tor-exit-nodes.txt" "$tor_file"
            local count=$(grep -c ',"true"' "$tor_file")
            log "Successfully updated TOR exit nodes: $count IPs"
        else
            log "ERROR: TOR exit node list is empty, keeping existing file"
        fi
    else
        log "ERROR: Failed to download TOR exit node list"
    fi
}

# Update abuse.ch Feodo Tracker (banking trojans/botnets)
update_feodo_tracker() {
    log "Updating Feodo Tracker IP list..."
    local feodo_url="https://feodotracker.abuse.ch/downloads/ipblocklist.txt"
    local feodo_file="${FEED_DIR}/feodo-tracker.txt"

    if curl -sS "$feodo_url" -o "${TEMP_DIR}/feodo_raw.txt" 2>/dev/null; then
        echo "# Feodo Tracker Botnet C2 IPs - Updated $(date)" > "${TEMP_DIR}/feodo-tracker.txt"
        echo "# Format: IP,\"true\"" >> "${TEMP_DIR}/feodo-tracker.txt"

        grep -v '^#' "${TEMP_DIR}/feodo_raw.txt" | \
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            awk '{print $1 ",\"true\""}' >> "${TEMP_DIR}/feodo-tracker.txt"

        if [ -s "${TEMP_DIR}/feodo-tracker.txt" ]; then
            mv "${TEMP_DIR}/feodo-tracker.txt" "$feodo_file"
            local count=$(grep -c ',"true"' "$feodo_file")
            log "Successfully updated Feodo Tracker: $count IPs"
        else
            log "ERROR: Feodo Tracker list is empty, keeping existing file"
        fi
    else
        log "ERROR: Failed to download Feodo Tracker list"
    fi
}

# Update emerging threats compromised IP list
update_emerging_threats() {
    log "Updating Emerging Threats compromised IP list..."
    local et_url="https://rules.emergingthreats.net/blockrules/compromised-ips.txt"
    local et_file="${FEED_DIR}/compromised-ips.txt"

    if curl -sS "$et_url" -o "${TEMP_DIR}/et_raw.txt" 2>/dev/null; then
        echo "# Emerging Threats Compromised IPs - Updated $(date)" > "${TEMP_DIR}/compromised-ips.txt"
        echo "# Format: IP,\"true\"" >> "${TEMP_DIR}/compromised-ips.txt"

        grep -v '^#' "${TEMP_DIR}/et_raw.txt" | \
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            awk '{print $1 ",\"true\""}' >> "${TEMP_DIR}/compromised-ips.txt"

        if [ -s "${TEMP_DIR}/compromised-ips.txt" ]; then
            mv "${TEMP_DIR}/compromised-ips.txt" "$et_file"
            local count=$(grep -c ',"true"' "$et_file")
            log "Successfully updated Emerging Threats: $count IPs"
        else
            log "ERROR: Emerging Threats list is empty, keeping existing file"
        fi
    else
        log "ERROR: Failed to download Emerging Threats list"
    fi
}

# Update Talos Intelligence reputation list
update_talos_reputation() {
    log "Updating Talos IP Reputation list..."
    local talos_url="https://talosintelligence.com/documents/ip-blacklist"
    local talos_file="${FEED_DIR}/talos-reputation.txt"

    if curl -sS "$talos_url" -o "${TEMP_DIR}/talos_raw.txt" 2>/dev/null; then
        echo "# Talos Intelligence IP Reputation - Updated $(date)" > "${TEMP_DIR}/talos-reputation.txt"
        echo "# Format: IP,\"true\"" >> "${TEMP_DIR}/talos-reputation.txt"

        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "${TEMP_DIR}/talos_raw.txt" | \
            awk '{print $1 ",\"true\""}' >> "${TEMP_DIR}/talos-reputation.txt"

        if [ -s "${TEMP_DIR}/talos-reputation.txt" ]; then
            mv "${TEMP_DIR}/talos-reputation.txt" "$talos_file"
            local count=$(grep -c ',"true"' "$talos_file" 2>/dev/null || echo "0")
            log "Successfully updated Talos Reputation: $count IPs"
        else
            log "WARNING: Talos Reputation list is empty or unavailable"
        fi
    else
        log "WARNING: Failed to download Talos Reputation list (may require authentication)"
    fi
}

# Update CDN IP ranges
update_cdn_ranges() {
    log "Updating CDN IP ranges..."
    local cdn_file="${FEED_DIR}/cdn-ip-lists.txt"

    echo "# CDN and Cloud Provider IP Ranges - Updated $(date)" > "${TEMP_DIR}/cdn-ip-lists.txt"
    echo "# Format: CIDR notation" >> "${TEMP_DIR}/cdn-ip-lists.txt"

    # AWS IP ranges
    log "  Fetching AWS IP ranges..."
    if curl -sS "https://ip-ranges.amazonaws.com/ip-ranges.json" -o "${TEMP_DIR}/aws.json" 2>/dev/null; then
        echo "# AWS CloudFront" >> "${TEMP_DIR}/cdn-ip-lists.txt"
        jq -r '.prefixes[] | select(.service=="CLOUDFRONT") | .ip_prefix' "${TEMP_DIR}/aws.json" >> "${TEMP_DIR}/cdn-ip-lists.txt" 2>/dev/null || true
    fi

    # Cloudflare IP ranges
    log "  Fetching Cloudflare IP ranges..."
    if curl -sS "https://www.cloudflare.com/ips-v4" -o "${TEMP_DIR}/cloudflare.txt" 2>/dev/null; then
        echo "# Cloudflare" >> "${TEMP_DIR}/cdn-ip-lists.txt"
        cat "${TEMP_DIR}/cloudflare.txt" >> "${TEMP_DIR}/cdn-ip-lists.txt"
    fi

    # Google Cloud IP ranges (requires gcloud CLI or manual update)
    log "  Google Cloud ranges require manual update or gcloud CLI"

    if [ -s "${TEMP_DIR}/cdn-ip-lists.txt" ]; then
        mv "${TEMP_DIR}/cdn-ip-lists.txt" "$cdn_file"
        local count=$(grep -c '^[0-9]' "$cdn_file" 2>/dev/null || echo "0")
        log "Successfully updated CDN ranges: $count CIDR blocks"
    else
        log "ERROR: CDN list is empty, keeping existing file"
    fi
}

# Reload Logstash to pick up new threat feeds
reload_logstash() {
    log "Reloading Logstash configuration..."
    if docker exec redelk-logstash kill -SIGHUP 1 2>/dev/null; then
        log "Logstash configuration reloaded"
    else
        log "WARNING: Could not reload Logstash (container may not be running)"
    fi
}

# Main execution
main() {
    log "Starting threat feed update..."

    # Ensure feed directory exists
    mkdir -p "$FEED_DIR"

    # Update all feeds
    update_tor_nodes
    update_feodo_tracker
    update_emerging_threats
    update_talos_reputation
    update_cdn_ranges

    # Reload Logstash
    reload_logstash

    log "Threat feed update completed"
}

# Run main function
main "$@"