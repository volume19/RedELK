import json
from pathlib import Path

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
TEMPLATE_DIR = PROJECT_ROOT / "elkserver" / "elasticsearch" / "index-templates"
LOGSTASH_DIR = PROJECT_ROOT / "elkserver" / "logstash" / "conf.d"


def _load_template(name: str) -> dict:
    return json.loads((TEMPLATE_DIR / name).read_text())


@pytest.mark.rag
@pytest.mark.unit
def test_rtops_template_contains_nested_fields():
    template = _load_template("rtops-template.json")
    properties = template["template"]["mappings"]["properties"]

    assert "infra" in properties
    assert "c2" in properties
    assert "beacon" in properties

    infra_log = properties["infra"]["properties"]["log"]["properties"]
    assert infra_log["type"]["type"] == "keyword"

    beacon_props = properties["beacon"]["properties"]
    assert beacon_props["id"]["type"] == "keyword"
    assert beacon_props["hostname"]["type"] == "keyword"


@pytest.mark.rag
@pytest.mark.unit
def test_target_index_routes_all_tags():
    config = (LOGSTASH_DIR / "80-target-index.conf").read_text()
    expected_routes = [
        "redirtraffic-%{+YYYY.MM.dd}",
        "rtops-%{+YYYY.MM.dd}",
        "credentials-%{+YYYY.MM.dd}",
        "ioc-%{+YYYY.MM.dd}",
        "screenshots-%{+YYYY.MM.dd}",
    ]

    for route in expected_routes:
        assert route in config, f"Missing route for {route}"

    assert "[@metadata][target_index]" in config


@pytest.mark.rag
@pytest.mark.unit
def test_outputs_use_metadata_index_and_env_credentials():
    config = (LOGSTASH_DIR / "90-outputs.conf").read_text()

    assert "%{[@metadata][target_index]}" in config
    assert "${LOGSTASH_ELASTIC_USERNAME}" in config
    assert "${LOGSTASH_ELASTIC_PASSWORD}" in config
