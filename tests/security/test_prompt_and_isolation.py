from pathlib import Path

import pytest
import yaml


PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _load_yaml(relative_path: str) -> dict:
    return yaml.safe_load((PROJECT_ROOT / relative_path).read_text())


@pytest.mark.security
@pytest.mark.unit
def test_c2_filebeat_enforces_tls():
    config = _load_yaml("c2servers/filebeat-cobaltstrike.yml")
    output = config["output.logstash"]

    assert output["ssl.enabled"] is True
    assert output["ssl.verification_mode"] == "certificate"
    assert any("REDELK_HOST" in host for host in output["hosts"])
    assert any(path.endswith("redelk-ca.crt") for path in output["ssl.certificate_authorities"])


@pytest.mark.security
@pytest.mark.unit
def test_c2_inputs_emit_nested_fields():
    config = _load_yaml("c2servers/filebeat-cobaltstrike.yml")
    inputs = config["filebeat.inputs"]

    assert inputs, "Expected at least one Filebeat input"
    for input_cfg in inputs:
        assert input_cfg.get("fields_under_root") is True
        assert input_cfg.get("fields", {}).get("infra", {}).get("log", {}).get("type") == "rtops"
        assert input_cfg.get("fields", {}).get("c2", {}).get("program") == "cobaltstrike"


@pytest.mark.security
@pytest.mark.unit
def test_redirector_profile_adds_role_and_tags():
    config = _load_yaml("redirs/filebeat-nginx.yml")
    processors = config.get("processors", [])

    add_fields = next((p["add_fields"] for p in processors if isinstance(p, dict) and "add_fields" in p), None)
    add_tags = next((p["add_tags"] for p in processors if isinstance(p, dict) and "add_tags" in p), None)

    assert add_fields is not None
    assert add_fields["fields"]["role"] == "redir"

    assert add_tags is not None
    assert set(add_tags["tags"]) >= {"redelk", "nginx"}
