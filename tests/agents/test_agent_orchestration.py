import os
import shutil

import pytest


@pytest.mark.agents
@pytest.mark.security
@pytest.mark.integration
@pytest.mark.usefixtures("env_file")
def test_beacon_manager_details_flow(data_dir, mock_cli_dir, command_runner):
    env = os.environ.copy()
    env["PATH"] = f"{mock_cli_dir}:{env['PATH']}"
    env["MOCK_CURL_SCENARIO"] = "beacon-list"
    env["MOCK_CURL_PAYLOAD"] = str(data_dir / "beacons" / "details_response.json")
    env["REAL_CURL"] = shutil.which("curl") or "curl"
    env.pop("ELASTIC_PASSWORD", None)

    result = command_runner(
        ["bash", "scripts/redelk-beacon-manager.sh", "details", "beacon-123"],
        env=env,
    )

    assert "Beacon Details" in result.stdout
    assert "Hostname: alpha" in result.stdout
    assert "Internal IP: 10.10.10.5" in result.stdout
    assert result.returncode == 0


@pytest.mark.agents
@pytest.mark.integration
@pytest.mark.usefixtures("env_file")
def test_beacon_manager_commands_limit(data_dir, mock_cli_dir, command_runner):
    env = os.environ.copy()
    env["PATH"] = f"{mock_cli_dir}:{env['PATH']}"
    env["MOCK_CURL_SCENARIO"] = "beacon-list"
    env["MOCK_CURL_PAYLOAD"] = str(data_dir / "beacons" / "commands_response.json")
    env["REAL_CURL"] = shutil.which("curl") or "curl"

    result = command_runner(
        ["bash", "scripts/redelk-beacon-manager.sh", "commands", "beacon-123", "1"],
        env=env,
    )

    assert "Recent Commands" in result.stdout
    assert result.stdout.count("shell") == 1
    assert "whoami" in result.stdout


@pytest.mark.agents
@pytest.mark.integration
@pytest.mark.usefixtures("env_file")
def test_beacon_manager_search_ioc(data_dir, mock_cli_dir, command_runner):
    env = os.environ.copy()
    env["PATH"] = f"{mock_cli_dir}:{env['PATH']}"
    env["MOCK_CURL_SCENARIO"] = "beacon-list"
    env["MOCK_CURL_PAYLOAD"] = str(data_dir / "beacons" / "search_response.json")
    env["REAL_CURL"] = shutil.which("curl") or "curl"

    result = command_runner(
        ["bash", "scripts/redelk-beacon-manager.sh", "search", "alpha"],
        env=env,
    )

    assert "Searching for IOC" in result.stdout
    assert "Found 1 matches" in result.stdout
    assert "Beacon: beacon-123" in result.stdout
