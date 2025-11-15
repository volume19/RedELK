#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "${ROOT_DIR}/tests/lib/testlib.sh"

stub_dir=$(mktemp -d)
backup_env=""
ENV_PATH="${ROOT_DIR}/elkserver/.env"
if [[ -f "$ENV_PATH" ]]; then
    backup_env=$(mktemp)
    cp "$ENV_PATH" "$backup_env"
fi

cleanup() {
    cleanup_dir "$stub_dir"
    if [[ -n "$backup_env" ]]; then
        mv "$backup_env" "$ENV_PATH" >/dev/null 2>&1 || true
    else
        rm -f "$ENV_PATH"
    fi
}
trap cleanup EXIT

cat <<'ENV' >"$ENV_PATH"
ELASTIC_PASSWORD=HealthCheckPass
ENV

cat <<'STUB' >"${stub_dir}/nc"
#!/usr/bin/env bash
port="${@: -1}"
case "$port" in
    9200|5601|5044)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
STUB
chmod +x "${stub_dir}/nc"

cat <<'STUB' >"${stub_dir}/docker"
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "ps" ]]; then
    echo "NAME STATUS"
    echo "redelk-elasticsearch   Up 10 minutes (healthy)"
    echo "redelk-logstash       Up 9 minutes (healthy)"
    echo "redelk-kibana         Up 9 minutes (healthy)"
    exit 0
fi
printf 'docker stub unexpected command: %s\n' "$*" >&2
exit 1
STUB
chmod +x "${stub_dir}/docker"

cat <<'STUB' >"${stub_dir}/curl"
#!/usr/bin/env bash
set -euo pipefail
url=""
while (($#)); do
    case "$1" in
        -o)
            shift 2
            continue
            ;;
        -u|-H|-d|--data|--header|-X|--request)
            shift 2
            continue
            ;;
        -s|-S|-L|--silent|--show-error|--fail)
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
    http://localhost:9200/_cluster/health)
        printf '{"status":"green"}'
        ;;
    http://localhost:9200/rtops-*/_count)
        printf '{"count":5}'
        ;;
    http://localhost:9200/redirtraffic-*/_count)
        printf '{"count":3}'
        ;;
    http://localhost:9200/alarms-*/_count)
        printf '{"count":1}'
        ;;
    http://localhost:9200/.monitoring-beats-*/_search*)
        printf '{"aggregations":{"beats":{"buckets":[{"key":"filebeat-smoke"}]}}}'
        ;;
    *)
        printf '{}'
        ;;
esac
STUB
chmod +x "${stub_dir}/curl"

cat <<'STUB' >"${stub_dir}/df"
#!/usr/bin/env bash
if [[ "$1" == "-h" ]]; then
    cat <<'OUT'
Filesystem      Size  Used Avail Use% Mounted on
overlay         100G   60G   40G  60% /var/lib/docker
OUT
else
    /bin/df "$@"
fi
STUB
chmod +x "${stub_dir}/df"

export PATH="${stub_dir}:$PATH"
output=$(bash "${ROOT_DIR}/scripts/redelk-health-check.sh" 2>&1) || {
    echo "$output" >&2
    fail "redelk-health-check.sh reported failure"
}

assert_contains "Health check complete" "$output"
assert_contains "rtops-*" "$output"
assert_contains "filebeat-smoke" "$output"
pass "health_check_test"
