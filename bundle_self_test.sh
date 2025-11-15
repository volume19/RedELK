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

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
normalize_self "$SCRIPT_PATH"

umask 077

readonly -a EXPECTED_CONF_FILES=(
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
    "80-target-index.conf"
    "90-outputs.conf"
)

readonly -a EXPECTED_TEMPLATE_FILES=(
    "alarm-template.json"
    "credentials-template.json"
    "ioc-template.json"
    "redelk-template.json"
    "redirtraffic-template.json"
    "rtops-template.json"
    "screenshots-template.json"
)

readonly -a EXPECTED_C2_CONFIGS=(
    "filebeat-cobaltstrike.yml"
    "filebeat-poshc2.yml"
)

readonly -a EXPECTED_REDIR_CONFIGS=(
    "filebeat-apache.yml"
    "filebeat-haproxy.yml"
    "filebeat-nginx.yml"
)

readonly -a EXPECTED_HELPER_SCRIPTS=(
    "check-redelk-data.sh"
    "deploy-filebeat-c2.sh"
    "deploy-filebeat-redir.sh"
    "redelk-beacon-manager.sh"
    "redelk-health-check.sh"
    "redelk-smoke-test.sh"
    "test-data-generator.sh"
    "update-threat-feeds.sh"
    "verify-deployment.sh"
)

readonly -a EXPECTED_THREAT_FEEDS=(
    "cdn-ip-lists.txt"
    "tor-exit-nodes.txt"
)

readonly DASHBOARD_FILE="redelk-main-dashboard.ndjson"

print_section() {
    local title="$1"
    printf '\n============================================================\n'
    printf '== %s ==\n' "$title"
    printf '============================================================\n'
}

check_dir_exists() {
    local description="$1"
    local path="$2"
    printf '[INFO] Checking directory %-25s -> %s\n' "$description" "$path"
    if [[ ! -d "$path" ]]; then
        echo "[ERROR] Missing directory: $path" >&2
        exit 1
    fi
}

verify_expected_files() {
    local description="$1"
    local base_dir="$2"
    shift 2
    local -a files=("$@")
    for name in "${files[@]}"; do
        local full_path="${base_dir}/${name}"
        if [[ ! -f "$full_path" ]]; then
            echo "[ERROR] Missing ${description}: ${full_path}" >&2
            exit 1
        fi
    done
    printf '[INFO] Verified %s (%d files) in %s\n' "$description" "${#files[@]}" "$base_dir"
}

main() {
readonly TARBALL="${1:-redelk-v3-deployment.tar.gz}"

if [[ ! -f "$TARBALL" ]]; then
    echo "[ERROR] Tarball not found: $TARBALL" >&2
    exit 1
fi

print_section "RedELK Bundle Self-Test"
printf '[INFO] Tarball path: %s\n' "$TARBALL"
printf '[INFO] Command: du -h %s\n' "$TARBALL"
du -h "$TARBALL"

TMPDIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

print_section "Extracting Bundle"
tar -xzf "$TARBALL" -C "$TMPDIR"
readonly BUNDLE_DIR="${TMPDIR}/DEPLOYMENT-BUNDLE"

if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "[ERROR] DEPLOYMENT-BUNDLE directory missing after extraction" >&2
    exit 1
fi

printf '[INFO] Bundle extracted to: %s\n' "$BUNDLE_DIR"
printf '[INFO] Command: ls -1 %s | head -n 20\n' "$BUNDLE_DIR"
(cd "$BUNDLE_DIR" && ls -1 | head -n 20)

readonly SOURCE_LOGSTASH_CONF_DIR="${BUNDLE_DIR}/elkserver/logstash/conf.d"
readonly SOURCE_TEMPLATE_DIR="${BUNDLE_DIR}/elkserver/elasticsearch/index-templates"
readonly SOURCE_DASHBOARD_DIR="${BUNDLE_DIR}/elkserver/kibana/dashboards"
readonly SOURCE_HELPER_DIR="${BUNDLE_DIR}/scripts"
readonly SOURCE_THREAT_FEED_DIR="${BUNDLE_DIR}/elkserver/logstash/threat-feeds"
readonly SOURCE_C2_DIR="${BUNDLE_DIR}/c2servers"
readonly SOURCE_REDIR_DIR="${BUNDLE_DIR}/redirs"

print_section "Validating Logstash Pipelines"
check_dir_exists "logstash/conf.d" "$SOURCE_LOGSTASH_CONF_DIR"
verify_expected_files "Logstash pipeline config" "$SOURCE_LOGSTASH_CONF_DIR" "${EXPECTED_CONF_FILES[@]}"
conf_count=$(find "$SOURCE_LOGSTASH_CONF_DIR" -maxdepth 1 -type f -name '*.conf' | wc -l)
printf '[INFO] logstash/conf.d contains %s *.conf files\n' "$conf_count"

print_section "Validating Elasticsearch Templates"
check_dir_exists "elasticsearch/index-templates" "$SOURCE_TEMPLATE_DIR"
verify_expected_files "Elasticsearch template" "$SOURCE_TEMPLATE_DIR" "${EXPECTED_TEMPLATE_FILES[@]}"
template_count=$(find "$SOURCE_TEMPLATE_DIR" -maxdepth 1 -type f -name '*.json' | wc -l)
printf '[INFO] index-templates contains %s *.json files\n' "$template_count"

print_section "Validating Kibana Dashboards"
check_dir_exists "kibana/dashboards" "$SOURCE_DASHBOARD_DIR"
verify_expected_files "Kibana dashboard" "$SOURCE_DASHBOARD_DIR" "$DASHBOARD_FILE"
dashboard_path="${SOURCE_DASHBOARD_DIR}/${DASHBOARD_FILE}"
dashboard_size=$(stat -c '%s' "$dashboard_path")
printf '[INFO] %s size=%s bytes\n' "$DASHBOARD_FILE" "$dashboard_size"
if (( dashboard_size < 2048 )); then
    echo "[ERROR] Dashboard ${DASHBOARD_FILE} too small (${dashboard_size} bytes)" >&2
    exit 1
fi

print_section "Validating Helper Assets"
check_dir_exists "scripts" "$SOURCE_HELPER_DIR"
verify_expected_files "helper script" "$SOURCE_HELPER_DIR" "${EXPECTED_HELPER_SCRIPTS[@]}"
check_dir_exists "logstash/threat-feeds" "$SOURCE_THREAT_FEED_DIR"
verify_expected_files "threat feed" "$SOURCE_THREAT_FEED_DIR" "${EXPECTED_THREAT_FEEDS[@]}"
check_dir_exists "c2servers" "$SOURCE_C2_DIR"
verify_expected_files "C2 Filebeat config" "$SOURCE_C2_DIR" "${EXPECTED_C2_CONFIGS[@]}"
check_dir_exists "redirs" "$SOURCE_REDIR_DIR"
verify_expected_files "redirector Filebeat config" "$SOURCE_REDIR_DIR" "${EXPECTED_REDIR_CONFIGS[@]}"

print_section "Validating Critical Scripts"
for script in install-redelk.sh redelk_ubuntu_deploy.sh; do
    if [[ ! -f "${BUNDLE_DIR}/${script}" ]]; then
        echo "[ERROR] Missing ${script}" >&2
        exit 1
    fi
    printf '[INFO] Found %s (mode %s)\n' "$script" "$(stat -c '%a' "${BUNDLE_DIR}/${script}")"
done

print_section "Self-Test Result"
echo "All required bundle contents verified"
printf 'Result: PASS\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
