import os
import shlex
import shutil
from pathlib import Path

import pytest


SCRIPT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "update-threat-feeds.sh"


@pytest.mark.integration
def test_threat_feed_updater_runs_offline(tmp_path, data_dir, mock_cli_dir, bash_runner):
    redekl_path = tmp_path / "redelk"
    feed_dir = redekl_path / "elkserver/logstash/threat-feeds"
    log_dir = redekl_path / "elkserver/logs"
    feed_dir.mkdir(parents=True)
    log_dir.mkdir(parents=True)

    env = os.environ.copy()
    env["REDELK_PATH"] = str(redekl_path)
    env["PATH"] = f"{mock_cli_dir}:{env['PATH']}"
    env["MOCK_CURL_SCENARIO"] = "threat-feeds"
    env["MOCK_HTTP_DIR"] = str(data_dir / "threat_feeds")
    env["REAL_CURL"] = shutil.which("curl") or "curl"

    quoted_script = shlex.quote(str(SCRIPT_PATH))
    snippet = """
source {script}
update_tor_nodes
update_feodo_tracker
update_emerging_threats
update_talos_reputation
update_cdn_ranges
""".format(script=quoted_script)
    bash_runner(snippet, env=env)

    tor_file = feed_dir / "tor-exit-nodes.txt"
    feodo_file = feed_dir / "feodo-tracker.txt"
    et_file = feed_dir / "compromised-ips.txt"
    talos_file = feed_dir / "talos-reputation.txt"
    cdn_file = feed_dir / "cdn-ip-lists.txt"

    assert tor_file.exists() and "203.0.113.50" in tor_file.read_text()
    assert feodo_file.exists() and "198.51.100.11" in feodo_file.read_text()
    assert et_file.exists() and "192.0.2.11" in et_file.read_text()
    assert talos_file.exists() and "203.0.113.200" in talos_file.read_text()
    cdn_contents = cdn_file.read_text()
    assert "198.18.0.0/15" in cdn_contents
    assert "203.0.113.0/24" in cdn_contents
