#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "${ROOT_DIR}/tests/lib/testlib.sh"

workspace=$(mktemp -d)
stub_dir=$(mktemp -d)

cleanup() {
    cleanup_dir "$workspace"
    cleanup_dir "$stub_dir"
}
trap cleanup EXIT

cat <<'STUB' >"${stub_dir}/curl"
#!/usr/bin/env bash
set -euo pipefail
outfile=""
url=""
while (($#)); do
    case "$1" in
        -o)
            outfile="$2"
            shift 2
            continue
            ;;
        -u|-H|-d|--data|--header|-X|--request)
            shift 2
            continue
            ;;
        -s|-S|-L|--silent|--show-error|--fail|--compressed)
            shift
            continue
            ;;
        *)
            if [[ "$1" == http* ]]; then
                url="$1"
            fi
            shift
            ;;
    esac
done
case "$url" in
    https://check.torproject.org/exit-addresses)
        cat <<'DATA' >"${outfile}"
ExitAddress 203.0.113.10 2024-05-12 12:34:00
DATA
        ;;
    https://feodotracker.abuse.ch/downloads/ipblocklist.txt)
        cat <<'DATA' >"${outfile}"
# comment
198.51.100.10
203.0.113.20
DATA
        ;;
    https://rules.emergingthreats.net/blockrules/compromised-ips.txt)
        cat <<'DATA' >"${outfile}"
#
192.0.2.1
DATA
        ;;
    https://talosintelligence.com/documents/ip-blacklist)
        cat <<'DATA' >"${outfile}"
198.51.100.50 some-info
DATA
        ;;
    https://ip-ranges.amazonaws.com/ip-ranges.json)
        cat <<'JSON' >"${outfile}"
{
  "prefixes": [
    {"ip_prefix": "198.51.100.0/24", "service": "CLOUDFRONT"},
    {"ip_prefix": "203.0.113.0/24", "service": "OTHER"}
  ]
}
JSON
        ;;
    https://www.cloudflare.com/ips-v4)
        cat <<'DATA' >"${outfile}"
203.0.113.0/24
DATA
        ;;
    http://localhost:9200/_cluster/health)
        printf '{"status":"green"}'
        ;;
    *)
        if [[ -n "$outfile" ]]; then
            : >"${outfile}"
        fi
        ;;
esac
STUB
chmod +x "${stub_dir}/curl"

cat <<'STUB' >"${stub_dir}/docker"
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "exec" ]]; then
    exit 0
fi
printf 'docker stub unexpected command: %s\n' "$*" >&2
exit 1
STUB
chmod +x "${stub_dir}/docker"

export REDELK_PATH="$workspace"
export PATH="${stub_dir}:$PATH"

output_file="${workspace}/run.log"
if ! bash "${ROOT_DIR}/scripts/update-threat-feeds.sh" >"$output_file" 2>&1; then
    cat "$output_file" >&2
    fail "update-threat-feeds.sh did not succeed"
fi

feed_dir="${workspace}/elkserver/logstash/threat-feeds"
log_file="${workspace}/elkserver/logs/threat-feed-update.log"

assert_dir_exists "$feed_dir"
assert_file_exists "${feed_dir}/tor-exit-nodes.txt"
assert_file_exists "${feed_dir}/feodo-tracker.txt"
assert_file_exists "${feed_dir}/compromised-ips.txt"
assert_file_exists "${feed_dir}/talos-reputation.txt"
assert_file_exists "${feed_dir}/cdn-ip-lists.txt"
assert_file_exists "$log_file"

tor_content=$(cat "${feed_dir}/tor-exit-nodes.txt")
assert_contains "203.0.113.10" "$tor_content"

cdn_content=$(cat "${feed_dir}/cdn-ip-lists.txt")
assert_contains "198.51.100.0/24" "$cdn_content"
assert_contains "203.0.113.0/24" "$cdn_content"

log_content=$(cat "$log_file")
assert_contains "Threat feed update completed" "$log_content"

pass "update_threat_feeds_test"
