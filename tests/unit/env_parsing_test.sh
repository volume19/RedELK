#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "${ROOT_DIR}/tests/lib/testlib.sh"

ENV_PATH="${ROOT_DIR}/elkserver/.env"
backup_env=""
if [[ -f "${ENV_PATH}" ]]; then
    backup_env=$(mktemp)
    cp "${ENV_PATH}" "$backup_env"
fi

cleanup() {
    if [[ -n "$backup_env" ]]; then
        mv "$backup_env" "${ENV_PATH}" >/dev/null 2>&1 || true
    else
        rm -f "${ENV_PATH}"
    fi
}
trap cleanup EXIT

cat <<'ENV' >"${ENV_PATH}"
ELASTIC_PASSWORD=FromEnvFile
CUSTOM_VALUE=/env/file/path
ENV

unset REDELK_PATH || true
unset REDELK_ROOT || true

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/update-threat-feeds.sh"

value_from_file=$(load_env_value CUSTOM_VALUE "/opt/RedELK")
assert_eq "/env/file/path" "$value_from_file" "load_env_value should prefer .env contents"

export CUSTOM_VALUE="/override/path"
value_from_env=$(load_env_value CUSTOM_VALUE "/opt/RedELK")
assert_eq "/override/path" "$value_from_env" "load_env_value should honor environment overrides"

unset CUSTOM_VALUE
rm -f "${ENV_PATH}"

default_value=$(load_env_value MISSING_KEY "/default/value")
assert_eq "/default/value" "$default_value" "load_env_value should fall back to provided default"

pass "env_parsing_test"
