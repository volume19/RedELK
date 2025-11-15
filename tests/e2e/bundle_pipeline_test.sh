#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "${ROOT_DIR}/tests/lib/testlib.sh"

bundle_path="${ROOT_DIR}/redelk-v3-deployment.tar.gz"
bundle_dir="${ROOT_DIR}/DEPLOYMENT-BUNDLE"

rm -rf "$bundle_dir" "$bundle_path"

create_output=$(bash "${ROOT_DIR}/create-bundle.sh" 2>&1)
assert_file_exists "$bundle_path" "deployment bundle not created"

selftest_output=$(bash "${ROOT_DIR}/bundle_self_test.sh" "$bundle_path" 2>&1)
assert_contains "Result: PASS" "$selftest_output" "self-test did not report pass status"

rm -rf "$bundle_dir" "$bundle_path"

pass "bundle_pipeline_test"
