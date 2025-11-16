import pytest


@pytest.mark.e2e
def test_bundle_creation_and_self_test(bundle_artifact, command_runner):
    assert bundle_artifact.exists()
    result = command_runner(["bash", "bundle_self_test.sh", str(bundle_artifact)])
    assert "Result: PASS" in result.stdout
