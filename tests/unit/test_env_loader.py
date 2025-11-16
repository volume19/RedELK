import os
import shlex
from pathlib import Path

import pytest


SCRIPT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "update-threat-feeds.sh"


def call_load_env_value(bash_runner, env, key: str, default: str = "") -> str:
    quoted_script = shlex.quote(str(SCRIPT_PATH))
    quoted_key = shlex.quote(key)
    quoted_default = shlex.quote(default)
    snippet = f"source {quoted_script}\nload_env_value {quoted_key} {quoted_default}"
    result = bash_runner(snippet, env=env)
    return result.stdout.strip()


@pytest.mark.unit
def test_load_env_value_prefers_environment(monkeypatch, env_file, bash_runner):
    env_file.write_text("CUSTOM_VALUE=/from-file\n")
    env = os.environ.copy()
    env["CUSTOM_VALUE"] = "/from-env"
    env["REDELK_PATH"] = str(env_file.parent.parent)

    value = call_load_env_value(bash_runner, env, "CUSTOM_VALUE", "/default")
    assert value == "/from-env"


@pytest.mark.unit
def test_load_env_value_reads_env_file(monkeypatch, env_file, bash_runner):
    env_file.write_text("CUSTOM_VALUE=/from-file\n")
    env = os.environ.copy()
    env.pop("CUSTOM_VALUE", None)
    env["REDELK_PATH"] = str(env_file.parent.parent)

    value = call_load_env_value(bash_runner, env, "CUSTOM_VALUE", "/default")
    assert value == "/from-file"


@pytest.mark.unit
def test_load_env_value_falls_back_to_default(monkeypatch, env_file, bash_runner):
    if env_file.exists():
        env_file.unlink()
    env = os.environ.copy()
    env.pop("MISSING_KEY", None)

    value = call_load_env_value(bash_runner, env, "MISSING_KEY", "/default")
    assert value == "/default"
