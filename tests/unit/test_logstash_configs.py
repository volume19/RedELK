from pathlib import Path

import pytest


@pytest.mark.unit
def test_target_index_conf_sets_metadata(project_root):
    target_path = project_root / "elkserver/logstash/conf.d/80-target-index.conf"
    text = target_path.read_text()
    assert "[@metadata][target_index]" in text
    assert "rtops" in text and "redirtraffic" in text


@pytest.mark.unit
def test_outputs_use_ingest_credentials(project_root):
    output_path = project_root / "elkserver/logstash/conf.d/90-outputs.conf"
    text = output_path.read_text()
    assert "%{[@metadata][target_index]}" in text
    assert "${LOGSTASH_ELASTIC_USERNAME}" in text
    assert "${LOGSTASH_ELASTIC_PASSWORD}" in text


@pytest.mark.unit
def test_detection_rules_reference_new_field_names(project_root):
    detect_path = project_root / "elkserver/logstash/conf.d/70-detection-threats.conf"
    text = detect_path.read_text()
    assert "infra][log][type" in text
    assert "rtops" in text
