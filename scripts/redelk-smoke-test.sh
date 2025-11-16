#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
readonly ENV_FILE="${SCRIPT_DIR}/../elkserver/.env"

read_env_value() {
    local key="$1"
    local value=""
    if [[ -f "${ENV_FILE}" ]]; then
        while IFS='=' read -r env_key env_val; do
            if [[ "${env_key}" == "$key" ]]; then
                value=${env_val%$'\r'}
            fi
        done <"${ENV_FILE}"
    fi
    printf '%s' "$value"
}

load_elastic_password() {
    if [[ -n "${ELASTIC_PASSWORD:-}" ]]; then
        printf '%s' "${ELASTIC_PASSWORD}"
        return 0
    fi

    local from_env
    from_env=$(read_env_value "ELASTIC_PASSWORD")
    if [[ -n "$from_env" ]]; then
        printf '%s' "$from_env"
        return 0
    fi

    printf '%s' "RedElk2024Secure"
}

ELASTIC_VERSION="$(read_env_value "ELASTIC_VERSION")"
[[ -z "$ELASTIC_VERSION" ]] && ELASTIC_VERSION="8.15.3"
REDELK_PATH="$(read_env_value "REDELK_PATH")"
[[ -z "$REDELK_PATH" ]] && REDELK_PATH="/opt/RedELK"
ES_PASS="$(load_elastic_password)"
ES_USER="${ES_USER:-elastic}"
ES_HOST="127.0.0.1"
ES_PORT="9200"
CERT_PATH="${REDELK_PATH}/certs/elkserver.crt"

if [[ ! -f "$CERT_PATH" ]]; then
    echo "[ERROR] Expected certificate at ${CERT_PATH} not found" >&2
    exit 1
fi

command -v docker >/dev/null 2>&1 || { echo "[ERROR] docker command not available" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl command not available" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq command not available" >&2; exit 1; }

query_count() {
    local index="$1"
    curl -s -u "${ES_USER}:${ES_PASS}" "http://${ES_HOST}:${ES_PORT}/${index}/_count" | jq -r '.count // 0'
}

COUNT_RTOPS_BEFORE=$(query_count "rtops-*" || echo 0)
COUNT_REDIR_BEFORE=$(query_count "redirtraffic-*" || echo 0)

tmpdir=$(mktemp -d)
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT

cat >"${tmpdir}/c2.log" <<'LOG'
05/12 12:34:56 [metadata] beacon_1234 10.10.10.5 TARGETHOST TARGETUSER explorer.exe 1234
LOG

cat >"${tmpdir}/redir.log" <<'LOG'
203.0.113.10 - - [12/May/2024:15:32:10 +0000] "GET / HTTP/1.1" 200 1024 "-" "Mozilla/5.0" "-" "-" "-" "-" "frontend" "backend"
LOG

cat >"${tmpdir}/filebeat.yml" <<'YAML'
filebeat.inputs:
- type: filestream
  id: smoke-c2
  enabled: true
  paths:
    - /smoke/c2.log
  fields:
    infra:
      log:
        type: rtops
    c2:
      program: cobaltstrike
      log:
        type: beacon
  fields_under_root: true

- type: filestream
  id: smoke-redir
  enabled: true
  paths:
    - /smoke/redir.log
  fields:
    infra:
      log:
        type: redirtraffic
    redir:
      program: apache
  fields_under_root: true

output.logstash:
  hosts: ['logstash:5044']
  ssl.enabled: true
  ssl.verification_mode: certificate
  ssl.certificate_authorities: ['/etc/pki/tls/certs/redelk-ca.crt']
  bulk_max_size: 512

setup.template.enabled: false
logging.level: info
YAML

network_name="${DOCKER_NETWORK_NAME:-}"
if [[ -z "$network_name" ]]; then
    compose_env="${REDELK_PATH}/elkserver/.env"
    if [[ -f "$compose_env" ]]; then
        compose_project=$(grep -E '^COMPOSE_PROJECT_NAME=' "$compose_env" | cut -d'=' -f2)
    fi
    compose_project="${compose_project:-redelk}"
    candidate="${compose_project}_redelk"
    if docker network inspect "$candidate" >/dev/null 2>&1; then
        network_name="$candidate"
    elif docker network inspect redelk >/dev/null 2>&1; then
        network_name="redelk"
    else
        echo "[ERROR] Could not determine Docker network for Filebeat (set DOCKER_NETWORK_NAME)" >&2
        exit 1
    fi
fi

echo "[INFO] Running Filebeat ${ELASTIC_VERSION} smoke container on network ${network_name}"
docker run --rm \
    --network "${network_name}" \
    -v "${tmpdir}:/smoke:ro" \
    -v "${tmpdir}/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro" \
    -v "${CERT_PATH}:/etc/pki/tls/certs/redelk-ca.crt:ro" \
    docker.elastic.co/beats/filebeat:"${ELASTIC_VERSION}" \
    filebeat -e --once >/dev/null

echo "[INFO] Waiting for documents to ingest"
sleep 5

COUNT_RTOPS_AFTER=$(query_count "rtops-*" || echo 0)
COUNT_REDIR_AFTER=$(query_count "redirtraffic-*" || echo 0)

RTOPS_DELTA=$((COUNT_RTOPS_AFTER - COUNT_RTOPS_BEFORE))
REDIR_DELTA=$((COUNT_REDIR_AFTER - COUNT_REDIR_BEFORE))

printf '[INFO] rtops before=%s after=%s delta=%s\n' "$COUNT_RTOPS_BEFORE" "$COUNT_RTOPS_AFTER" "$RTOPS_DELTA"
printf '[INFO] redirtraffic before=%s after=%s delta=%s\n' "$COUNT_REDIR_BEFORE" "$COUNT_REDIR_AFTER" "$REDIR_DELTA"

if (( RTOPS_DELTA <= 0 )); then
    echo "[ERROR] Smoke test did not index C2 data" >&2
    exit 1
fi

if (( REDIR_DELTA <= 0 )); then
    echo "[ERROR] Smoke test did not index redirector data" >&2
    exit 1
fi

echo "[INFO] Smoke test succeeded"
