import shlex
import shutil
import subprocess
from pathlib import Path
from typing import Callable, Dict, Optional

import pytest


@pytest.fixture(scope="session")
def project_root() -> Path:
    return Path(__file__).resolve().parent.parent


@pytest.fixture
def env_file(project_root: Path):
    env_path = project_root / "elkserver/.env"
    original_bytes: Optional[bytes] = env_path.read_bytes() if env_path.exists() else None
    yield env_path
    if original_bytes is None:
        if env_path.exists():
            env_path.unlink()
    else:
        env_path.write_bytes(original_bytes)


@pytest.fixture(scope="session")
def fixtures_dir(project_root: Path) -> Path:
    return project_root / "tests" / "fixtures"


@pytest.fixture(scope="session")
def data_dir(fixtures_dir: Path) -> Path:
    return fixtures_dir / "data"


@pytest.fixture
def bash_runner(project_root: Path) -> Callable[[str, Optional[Dict[str, str]]], subprocess.CompletedProcess]:
    def _run(snippet: str, env: Optional[Dict[str, str]] = None, check: bool = True) -> subprocess.CompletedProcess:
        quoted_root = shlex.quote(str(project_root))
        script = f"set -euo pipefail\ncd {quoted_root}\n{snippet}"
        proc = subprocess.run(
            ["bash", "-c", script],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        if check and proc.returncode != 0:
            raise AssertionError(
                f"Command failed with code {proc.returncode}:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
            )
        return proc

    return _run


@pytest.fixture
def command_runner(project_root: Path) -> Callable[[list, Optional[Dict[str, str]]], subprocess.CompletedProcess]:
    def _run(cmd: list, env: Optional[Dict[str, str]] = None, check: bool = True) -> subprocess.CompletedProcess:
        proc = subprocess.run(
            cmd,
            cwd=project_root,
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )
        if check and proc.returncode != 0:
            raise AssertionError(
                f"Command {' '.join(cmd)} failed: {proc.stderr or proc.stdout}"
            )
        return proc

    return _run


@pytest.fixture
def mock_cli_dir(tmp_path) -> Path:
    bin_dir = tmp_path / "mock-bin"
    bin_dir.mkdir()

    curl_script = bin_dir / "curl"
    curl_script.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
scenario="${MOCK_CURL_SCENARIO:-}"
if [[ "$scenario" == "beacon-list" ]]; then
    cat "${MOCK_CURL_PAYLOAD:?MOCK_CURL_PAYLOAD not set}"
    exit 0
fi
if [[ "$scenario" == "threat-feeds" ]]; then
    url=""
    output=""
    while (($#)); do
        case "$1" in
            -o)
                shift
                output="$1"
                ;;
            http*)
                url="$1"
                ;;
        esac
        shift || true
    done
    if [[ -z "$output" ]]; then
        echo "mock curl: missing -o target" >&2
        exit 1
    fi
    base=$(basename "$url")
    fixture="${MOCK_HTTP_DIR:?MOCK_HTTP_DIR not set}/${base}"
    if [[ ! -f "$fixture" ]]; then
        echo "mock curl: no fixture for $base" >&2
        exit 1
    fi
    cp "$fixture" "$output"
    exit 0
fi
real_curl="${REAL_CURL:-$(command -v curl)}"
exec "$real_curl" "$@"
"""
    )
    curl_script.chmod(0o755)

    docker_script = bin_dir / "docker"
    docker_script.write_text(
        """#!/usr/bin/env bash
if [[ "${MOCK_DOCKER_ALLOW:-0}" == "1" ]]; then
    exit 0
fi
echo "mock docker invoked: $*" >&2
exit 1
"""
    )
    docker_script.chmod(0o755)

    return bin_dir


@pytest.fixture
def bundle_artifact(project_root: Path, command_runner) -> Path:
    bundle_path = project_root / "redelk-v3-deployment.tar.gz"
    bundle_dir = project_root / "DEPLOYMENT-BUNDLE"
    if bundle_path.exists():
        bundle_path.unlink()
    if bundle_dir.exists():
        shutil.rmtree(bundle_dir)

    command_runner(["bash", "create-bundle.sh"])

    yield bundle_path

    if bundle_dir.exists():
        shutil.rmtree(bundle_dir)
    if bundle_path.exists():
        bundle_path.unlink()
