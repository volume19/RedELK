#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "${ROOT_DIR}/tests/lib/testlib.sh"

tmp_root=$(mktemp -d)
stub_dir=$(mktemp -d)

cleanup() {
    cleanup_dir "$tmp_root"
    cleanup_dir "$stub_dir"
}
trap cleanup EXIT

mkdir -p "${tmp_root}/elkserver" "${tmp_root}/scripts" "${tmp_root}/c2servers" "${tmp_root}/redirs" "${tmp_root}/certs"
cp -R "${ROOT_DIR}/c2servers"/* "${tmp_root}/c2servers/"
cp -R "${ROOT_DIR}/redirs"/* "${tmp_root}/redirs/"
cp -R "${ROOT_DIR}/scripts"/* "${tmp_root}/scripts/"
cp -R "${ROOT_DIR}/elkserver/elasticsearch" "${tmp_root}/elkserver/"
cp -R "${ROOT_DIR}/elkserver/logstash" "${tmp_root}/elkserver/"
cp -R "${ROOT_DIR}/elkserver/kibana" "${tmp_root}/elkserver/"

mkdir -p "${tmp_root}/elkserver/logstash/pipelines"
touch "${tmp_root}/elkserver/logstash/pipelines/main.conf"
mkdir -p "${tmp_root}/elkserver/config"
cat <<'KIBANA' >"${tmp_root}/elkserver/config/kibana.yml"
server.host: 0.0.0.0
KIBANA
mkdir -p "${tmp_root}/elkserver/nginx"
cat <<'NGINX' >"${tmp_root}/elkserver/nginx/kibana.conf"
server { listen 443 ssl; }
NGINX
touch "${tmp_root}/elkserver/nginx/htpasswd"
cat <<'ENV' >"${tmp_root}/elkserver/.env"
ELASTIC_PASSWORD=IntegrationPass
ENV
cat <<'COMPOSE' >"${tmp_root}/elkserver/docker-compose.yml"
version: '3.8'
COMPOSE
cat <<'LOGSTASH' >"${tmp_root}/elkserver/logstash/logstash.yml"
pipeline.workers: 2
LOGSTASH
cat <<'PIPELINES' >"${tmp_root}/elkserver/logstash/pipelines.yml"
- pipeline.id: main
  path.config: /usr/share/logstash/pipeline
PIPELINES

touch "${tmp_root}/certs/elkserver.crt"
touch "${tmp_root}/certs/elkserver.key"

cat <<'STUB' >"${stub_dir}/nc"
#!/usr/bin/env bash
port="${@: -1}"
case "$port" in
    9200|5601|5044|80|443)
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
case "$1" in
    inspect)
        shift
        format=""
        if [[ "$1" == "-f" ]]; then
            format="$2"
            shift 2
        fi
        name="$1"
        case "$format" in
            "{{.State.Status}}")
                echo "running"
                ;;
            "{{.State.Health.Status}}")
                echo "healthy"
                ;;
            *)
                echo "running"
                ;;
        esac
        ;;
    exec)
        exit 0
        ;;
    *)
        echo "redelk-$1 Up" >&2
        ;;
esac
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
    http://localhost:9200/_index_template/rtops)
        printf '{"name":"rtops"}'
        ;;
    http://localhost:9200/_index_template/redirtraffic)
        printf '{"name":"redirtraffic"}'
        ;;
    http://localhost:9200/_index_template/alarms)
        printf '{"name":"alarms"}'
        ;;
    http://localhost:9200/_cluster/health)
        printf '{"status":"green"}'
        ;;
    *)
        printf '{}'
        ;;
esac
STUB
chmod +x "${stub_dir}/curl"

cat <<'STUB' >"${stub_dir}/sysctl"
#!/usr/bin/env bash
echo 262144
STUB
chmod +x "${stub_dir}/sysctl"

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

cat <<'STUB' >"${stub_dir}/free"
#!/usr/bin/env bash
cat <<'OUT'
              total        used        free      shared  buff/cache   available
Mem:           4096         500        3000          10          596        3200
Swap:             0           0           0
OUT
STUB
chmod +x "${stub_dir}/free"

cat <<'STUB' >"${stub_dir}/crontab"
#!/usr/bin/env bash
if [[ "$1" == "-l" ]]; then
    echo "0 * * * * /opt/RedELK/scripts/update-threat-feeds.sh"
else
    exit 1
fi
STUB
chmod +x "${stub_dir}/crontab"

export PATH="${stub_dir}:$PATH"
REDELK_ROOT="$tmp_root" output=$(REDELK_ROOT="$tmp_root" bash "${ROOT_DIR}/scripts/verify-deployment.sh" 2>&1) || {
    echo "$output" >&2
    fail "verify-deployment.sh reported failure"
}

assert_contains "RedELK deployment verification PASSED" "$output"
pass "verify_deployment_test"
