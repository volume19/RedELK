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

print_section() {
    local title="$1"
    printf '\n============================================================\n'
    printf '== %s ==\n' "$title"
    printf '============================================================\n'
}

print_section "RedELK Bundle Installer"
printf '[INFO] Script directory: %s\n' "$SCRIPT_DIR"
printf '[INFO] Checking for redelk_ubuntu_deploy.sh\n'

readonly DEPLOY_SCRIPT="${SCRIPT_DIR}/redelk_ubuntu_deploy.sh"

if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    echo "[ERROR] redelk_ubuntu_deploy.sh not found next to install script" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Must run as root (use sudo)" >&2
    exit 1
fi

chmod +x "$DEPLOY_SCRIPT"

printf '[INFO] Executing deployment script...\n'
exec /usr/bin/env bash "$DEPLOY_SCRIPT" "$@"
