from pathlib import Path

import pytest
import yaml


@pytest.mark.unit
@pytest.mark.security
@pytest.mark.parametrize(
    "relative_path",
    [
        Path("c2servers/filebeat-cobaltstrike.yml"),
        Path("redirs/filebeat-nginx.yml"),
    ],
)
def test_filebeat_configs_use_tls_and_nested_fields(project_root, relative_path):
    config_path = project_root / relative_path
    data = yaml.safe_load(config_path.read_text())

    inputs = data.get("filebeat.inputs", [])
    assert inputs, f"{relative_path} missing filebeat.inputs"
    if "c2servers" in str(relative_path):
        allowed_types = {"rtops"}
    else:
        allowed_types = {"redirtraffic", "redirerror"}
    for entry in inputs:
        assert entry.get("fields_under_root") is True, f"{relative_path} missing fields_under_root"
        infra = entry.get("fields", {}).get("infra", {}).get("log", {})
        assert (
            infra.get("type") in allowed_types
        ), f"{relative_path} inputs must emit infra.log.type in {sorted(allowed_types)}"

    output = data.get("output.logstash") or data.get("output", {}).get("logstash")
    assert output, f"{relative_path} missing logstash output"
    assert output.get("ssl.enabled") is True
    hosts = output.get("hosts") or []
    assert any("REDELK_HOST" in host for host in hosts), f"{relative_path} must keep REDELK_HOST placeholder"


@pytest.mark.unit
def test_cobaltstrike_processors_tag_records(project_root):
    config_path = project_root / "c2servers/filebeat-cobaltstrike.yml"
    data = yaml.safe_load(config_path.read_text())
    processors = data.get("processors", [])
    add_tags = next((p for p in processors if "add_tags" in p), None)
    assert add_tags is not None
    tags = add_tags["add_tags"]["tags"]
    assert "redelk" in tags
    assert "cobaltstrike" in tags
