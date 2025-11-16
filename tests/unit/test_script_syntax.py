from pathlib import Path

import pytest


SCRIPTS = [
    "scripts/update-threat-feeds.sh",
    "scripts/redelk-beacon-manager.sh",
    "scripts/deploy-filebeat-c2.sh",
    "scripts/deploy-filebeat-redir.sh",
    "scripts/check-redelk-data.sh",
    "scripts/redelk-smoke-test.sh",
]


@pytest.mark.unit
@pytest.mark.parametrize("script", SCRIPTS)
def test_shell_scripts_pass_syntax_check(project_root, script, command_runner):
    path = project_root / script
    assert path.exists(), f"Missing script {script}"
    command_runner(["bash", "-n", str(path)])
