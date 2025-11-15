#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly TEST_ROOT

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}" 
    if [[ "$expected" != "$actual" ]]; then
        if [[ -n "$message" ]]; then
            fail "$message (expected='$expected' actual='$actual')"
        else
            fail "expected '$expected' got '$actual'"
        fi
    fi
}

assert_ne() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-}"
    if [[ "$not_expected" == "$actual" ]]; then
        if [[ -n "$message" ]]; then
            fail "$message (unexpected='$actual')"
        else
            fail "unexpected '$actual'"
        fi
    fi
}

assert_file_exists() {
    local path="$1"
    local message="${2:-missing file: $path}"
    [[ -f "$path" ]] || fail "$message"
}

assert_dir_exists() {
    local path="$1"
    local message="${2:-missing dir: $path}"
    [[ -d "$path" ]] || fail "$message"
}

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local message="${3:-string does not contain '$needle'}"
    [[ "$haystack" == *"$needle"* ]] || fail "$message"
}

run_command() {
    local description="$1"
    shift
    "$@" || fail "command failed: $description"
}

create_tempdir() {
    mktemp -d
}

# shellcheck disable=SC2317
cleanup_dir() {
    local dir="$1"
    [[ -d "$dir" ]] && rm -rf "$dir"
}
