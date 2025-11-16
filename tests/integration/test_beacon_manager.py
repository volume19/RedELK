import os
import shutil

import pytest


@pytest.mark.integration
@pytest.mark.security
def test_beacon_manager_lists_records(env_file, data_dir, mock_cli_dir, command_runner):
    env_file.write_text("ELASTIC_PASSWORD=FromEnvFile\n")

    env = os.environ.copy()
    env.pop("ELASTIC_PASSWORD", None)
    env["PATH"] = f"{mock_cli_dir}:{env['PATH']}"
    env["MOCK_CURL_SCENARIO"] = "beacon-list"
    env["MOCK_CURL_PAYLOAD"] = str(data_dir / "beacons/list_response.json")
    env["REAL_CURL"] = shutil.which("curl") or "curl"

    result = command_runner(["bash", "scripts/redelk-beacon-manager.sh", "list"], env=env)
    assert "Active Beacons" in result.stdout
    assert "beacon-123" in result.stdout
    assert "alpha" in result.stdout
