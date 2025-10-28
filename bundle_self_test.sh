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
    "90-outputs.conf"
)

readonly -a EXPECTED_TEMPLATE_FILES=(
    "alarm-template.json"
    "redirtraffic-template.json"
    "rtops-template.json"
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
    "redelk-beacon-manager.sh"
    "redelk-health-check.sh"
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

print_section "Validating Logstash Pipelines"
printf '[INFO] Command: (cd %s && ls -1 *.conf | wc -l)\n' "$BUNDLE_DIR"
conf_count=$(cd "$BUNDLE_DIR" && ls -1 *.conf | wc -l)
printf 'conf_count=%s\n' "$conf_count"
if (( conf_count != ${#EXPECTED_CONF_FILES[@]} )); then
    echo "[ERROR] Expected ${#EXPECTED_CONF_FILES[@]} .conf files, found ${conf_count}" >&2
    exit 1
fi
for name in "${EXPECTED_CONF_FILES[@]}"; do
    if [[ ! -f "${BUNDLE_DIR}/${name}" ]]; then
        echo "[ERROR] Missing pipeline config: ${name}" >&2
        exit 1
    fi
done

print_section "Validating Elasticsearch Templates"
printf '[INFO] Command: (cd %s && ls -1 *-template.json | wc -l)\n' "$BUNDLE_DIR"
template_count=$(cd "$BUNDLE_DIR" && ls -1 *-template.json | wc -l)
printf 'template_count=%s\n' "$template_count"
if (( template_count != ${#EXPECTED_TEMPLATE_FILES[@]} )); then
    echo "[ERROR] Expected ${#EXPECTED_TEMPLATE_FILES[@]} templates, found ${template_count}" >&2
    exit 1
fi
for name in "${EXPECTED_TEMPLATE_FILES[@]}"; do
    if [[ ! -f "${BUNDLE_DIR}/${name}" ]]; then
        echo "[ERROR] Missing template: ${name}" >&2
        exit 1
    fi
done

print_section "Validating Kibana Dashboards"
printf '[INFO] Command: (cd %s && ls -1 *.ndjson | wc -l)\n' "$BUNDLE_DIR"
dash_count=$(cd "$BUNDLE_DIR" && ls -1 *.ndjson | wc -l)
printf 'dashboard_count=%s\n' "$dash_count"
if (( dash_count < 1 )); then
    echo "[ERROR] No .ndjson dashboards found" >&2
    exit 1
fi
dashboard_path="${BUNDLE_DIR}/${DASHBOARD_FILE}"
if [[ ! -f "$dashboard_path" ]]; then
    echo "[ERROR] Missing dashboard file ${DASHBOARD_FILE}" >&2
    exit 1
fi
dashboard_size=$(stat -c '%s' "$dashboard_path")
printf 'dashboard_size_bytes=%s\n' "$dashboard_size"
if (( dashboard_size < 2048 )); then
    echo "[ERROR] Dashboard ${DASHBOARD_FILE} too small (${dashboard_size} bytes)" >&2
    exit 1
fi

print_section "Validating Helper Assets"
for name in "${EXPECTED_HELPER_SCRIPTS[@]}"; do
    if [[ ! -f "${BUNDLE_DIR}/${name}" ]]; then
        echo "[ERROR] Missing helper script ${name}" >&2
        exit 1
    fi
done
for name in "${EXPECTED_THREAT_FEEDS[@]}"; do
    if [[ ! -f "${BUNDLE_DIR}/${name}" ]]; then
        echo "[ERROR] Missing threat feed ${name}" >&2
        exit 1
    fi
done
for name in "${EXPECTED_C2_CONFIGS[@]}"; do
    if [[ ! -f "${BUNDLE_DIR}/${name}" ]]; then
        echo "[ERROR] Missing C2 Filebeat config ${name}" >&2
        exit 1
    fi
done
for name in "${EXPECTED_REDIR_CONFIGS[@]}"; do
    if [[ ! -f "${BUNDLE_DIR}/${name}" ]]; then
        echo "[ERROR] Missing redirector Filebeat config ${name}" >&2
        exit 1
    fi
done

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
