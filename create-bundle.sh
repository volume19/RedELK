#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

normalize_self() {
    local target="$1"
    local modified=false
    if LC_ALL=C grep -q $'\r' "$target"; then
        local tmp
        tmp=$(mktemp)
        tr -d '\r' <"$target" >"$tmp"
        cat "$tmp" >"$target"
        rm -f "$tmp"
        modified=true
    fi
    local bom
    bom=$(head -c 3 "$target" | od -An -t x1 | tr -d ' \n')
    if [[ "$bom" == "efbbbf" ]]; then
        local tmp
        tmp=$(mktemp)
        tail -c +4 "$target" >"$tmp"
        cat "$tmp" >"$target"
        rm -f "$tmp"
        modified=true
    fi
    if [[ "$modified" == true ]]; then
        printf '[INFO] Normalized line endings for %s\n' "$target"
    fi
}

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
readonly SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
normalize_self "$SCRIPT_PATH"

umask 077

readonly BUNDLE_DIR="DEPLOYMENT-BUNDLE"
readonly OUTPUT_TARBALL="redelk-v3-deployment.tar.gz"

readonly -a PIPELINE_FILES=(
    "10-input-filebeat.conf"
    "20-filter-redir-apache.conf"
    "21-filter-redir-nginx.conf"
    "22-filter-redir-haproxy.conf"
    "50-filter-c2-cobaltstrike.conf"
    "51-filter-c2-poshc2.conf"
    "60-enrich-geoip.conf"
    "61-enrich-cdn.conf"
    "62-enrich-useragent.conf"
    "70-detection-threats.conf"
    "90-outputs.conf"
)

readonly -a TEMPLATE_FILES=(
    "alarm-template.json"
    "redirtraffic-template.json"
    "rtops-template.json"
)

readonly -a THREAT_FEED_FILES=(
    "cdn-ip-lists.txt"
    "tor-exit-nodes.txt"
)

readonly -a HELPER_SCRIPTS=(
    "check-redelk-data.sh"
    "redelk-beacon-manager.sh"
    "redelk-health-check.sh"
    "test-data-generator.sh"
    "update-threat-feeds.sh"
    "verify-deployment.sh"
)

readonly -a C2_CONFIGS=(
    "filebeat-cobaltstrike.yml"
    "filebeat-poshc2.yml"
)

readonly -a REDIR_CONFIGS=(
    "filebeat-apache.yml"
    "filebeat-haproxy.yml"
    "filebeat-nginx.yml"
)

readonly DASHBOARD_FILE="redelk-main-dashboard.ndjson"

normalize_copy() {
    local src="$1"
    local dest="$2"
    local mode="$3"
    python3 - "$src" "$dest" <<'PY'
import pathlib, sys
src_path = pathlib.Path(sys.argv[1])
dest_path = pathlib.Path(sys.argv[2])
data = src_path.read_bytes()
if data.startswith(b"\xef\xbb\xbf"):
    data = data[3:]
data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
dest_path.write_bytes(data)
PY
    chmod "$mode" "$dest"
}

copy_required_file() {
    local source="$1"
    local destination="$2"
    local mode="$3"
    if [[ ! -f "$source" ]]; then
        echo "[ERROR] Missing required file: $source" >&2
        exit 1
    fi
    normalize_copy "$source" "$destination" "$mode"
    printf '[INFO] Copied %s -> %s\n' "$source" "$destination"
}

print_section() {
    local title="$1"
    printf '\n============================================================\n'
    printf '== %s ==\n' "$title"
    printf '============================================================\n'
}

prepare_bundle() {
    rm -rf "$BUNDLE_DIR"
    mkdir -p "$BUNDLE_DIR"
}

declare -a sections=(
    "Logstash pipeline configs" "${SCRIPT_DIR}/elkserver/logstash/conf.d" 0644 "PIPELINE_FILES[@]"
    "Elasticsearch templates" "${SCRIPT_DIR}/elkserver/elasticsearch/index-templates" 0644 "TEMPLATE_FILES[@]"
    "Threat feeds" "${SCRIPT_DIR}/elkserver/logstash/threat-feeds" 0644 "THREAT_FEED_FILES[@]"
    "Helper scripts" "${SCRIPT_DIR}/scripts" 0755 "HELPER_SCRIPTS[@]"
    "C2 Filebeat configs" "${SCRIPT_DIR}/c2servers" 0644 "C2_CONFIGS[@]"
    "Redirector Filebeat configs" "${SCRIPT_DIR}/redirs" 0644 "REDIR_CONFIGS[@]"
)

print_section "Preparing bundle directory"
prepare_bundle

print_section "Copying core scripts"
copy_required_file "${SCRIPT_DIR}/VERSION" "${BUNDLE_DIR}/VERSION" 0644
copy_required_file "${SCRIPT_DIR}/redelk_ubuntu_deploy.sh" "${BUNDLE_DIR}/redelk_ubuntu_deploy.sh" 0755
copy_required_file "${SCRIPT_DIR}/install-redelk.sh" "${BUNDLE_DIR}/install-redelk.sh" 0755

for ((i=0; i<${#sections[@]}; i+=4)); do
    local title="${sections[i]}"
    local source_dir="${sections[i+1]}"
    local mode="${sections[i+2]}"
    local array_ref="${sections[i+3]}"

    print_section "Copying ${title}"
    local name
    for name in "${!array_ref}"; do
        copy_required_file "${source_dir}/${name}" "${BUNDLE_DIR}/${name}" "$mode"
    done
    unset name
    unset title source_dir mode array_ref
    shift 0
    set +u
    set -u
    
# purposely blank

done

print_section "Copying Kibana dashboards"
copy_required_file "${SCRIPT_DIR}/elkserver/kibana/dashboards/${DASHBOARD_FILE}" "${BUNDLE_DIR}/${DASHBOARD_FILE}" 0644

print_section "Creating archive"
tar -czf "$OUTPUT_TARBALL" "$BUNDLE_DIR"
du -h "$OUTPUT_TARBALL"

print_section "Bundle complete"
printf 'Created %s\n' "$OUTPUT_TARBALL"