#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
    cat <<USAGE
Usage: ${0##*/} [all|unit|integration|e2e]
USAGE
}

run_suite() {
    local suite="$1"
    local suite_dir="${ROOT_DIR}/tests/${suite}"
    if [[ ! -d "$suite_dir" ]]; then
        echo "[WARN] Suite '${suite}' does not exist"
        return
    fi
    shopt -s nullglob
    local scripts=("${suite_dir}"/*.sh)
    shopt -u nullglob
    if [[ ${#scripts[@]} -eq 0 ]]; then
        echo "[INFO] No ${suite} tests to run"
        return
    fi
    for script in "${scripts[@]}"; do
        echo "[RUN] ${script#$ROOT_DIR/}"
        bash "$script"
    done
}

SUITE="${1:-all}"
case "$SUITE" in
    all)
        run_suite unit
        run_suite integration
        run_suite e2e
        ;;
    unit|integration|e2e)
        run_suite "$SUITE"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown suite: $SUITE" >&2
        usage
        exit 1
        ;;
esac
