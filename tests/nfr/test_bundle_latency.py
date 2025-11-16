import time

import pytest


@pytest.mark.nfr
def test_bundle_self_test_completes_quickly(bundle_artifact, command_runner):
    start = time.perf_counter()
    result = command_runner(["bash", "bundle_self_test.sh", str(bundle_artifact)])
    duration = time.perf_counter() - start
    assert "Result: PASS" in result.stdout
    assert duration < 10, f"bundle self-test took too long: {duration:.2f}s"
