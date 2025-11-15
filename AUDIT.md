# RedELK Debugging Audit

## Overview
This report captures the most impactful runtime, configuration, and tooling risks identified during a code-level audit of the current RedELK repository. Findings are grouped by category, with the affected components and recommended remediation strategies noted for each item.

## Logstash pipeline configuration mismatches
- **Threat feed path drift:** The pipeline that detects CDN traffic still reads from `/usr/share/logstash/cdn-ip-lists.txt`, while the deployment now ships threat feeds under `/opt/RedELK/elkserver/logstash/threat-feeds` and mounts them into containers at `/usr/share/logstash/config/threat-feeds`. As a result, the `cidr` lookups never see the updated feed files. Update the Logstash configs (and the TOR translate lookups) to reference `/usr/share/logstash/config/threat-feeds/*.txt`, or adjust the docker-compose volume to mount feeds at the legacy path.【F:elkserver/logstash/conf.d/61-enrich-cdn.conf†L1-L70】【F:redelk_ubuntu_deploy.sh†L520-L637】
- **Alarm translate dictionaries:** The alarm pipeline still uses `/usr/share/logstash/tor-exit-nodes.txt`, which no longer exists because the bundle relocated the feed files into the threat-feeds directory. Align the `translate` dictionary paths with the deployed location so TOR detection works again.【F:elkserver/logstash/conf.d/70-detection-threats.conf†L1-L87】【F:redelk_ubuntu_deploy.sh†L520-L637】

## Operational tooling stability
- **Verification script exits prematurely:** `scripts/verify-deployment.sh` runs with `set -euo pipefail`, but every helper such as `check_container` returns non-zero on failure and the caller does not guard those returns. The script therefore aborts on the first failing check instead of reporting a full summary. Wrap each call in conditional handling (e.g., `if ! check_container ...; then ...; fi`) or drop `set -e` and rely on explicit status tracking.【F:scripts/verify-deployment.sh†L1-L200】
- **Health check script aborts early:** The health check utility has the same `set -euo pipefail` pattern. A single missing container or closed port terminates the script before it can print the remaining diagnostics. Mirror the fix above so the tool can collect all observations even when parts of the stack are degraded.【F:scripts/redelk-health-check.sh†L1-L142】

## Monitoring coverage accuracy
- **Redis references in health tooling:** The health check script still expects a `redelk-redis` container and a Redis service on port 6379, but the docker-compose stack built by `redelk_ubuntu_deploy.sh` no longer includes Redis. Remove or gate the Redis checks so operators are not alerted on components that no longer exist.【F:scripts/redelk-health-check.sh†L54-L70】【F:redelk_ubuntu_deploy.sh†L520-L637】

## Configuration consistency
- **Hard-coded Elasticsearch credentials:** `scripts/check-redelk-data.sh` always queries Elasticsearch with `RedElk2024Secure`, ignoring the value users might set through the deployment `.env`. Load credentials from the same `.env` file or accept them via environment variables so the diagnostics succeed when operators override the default password.【F:scripts/check-redelk-data.sh†L1-L35】【F:redelk_ubuntu_deploy.sh†L432-L452】

## Follow-up recommendations
1. Patch the Logstash configurations (or compose mounts) so enrichment filters and translate dictionaries point to the actual threat feed paths created during deployment.
2. Refactor the verification and health-check utilities to manage failures internally instead of exiting on the first error, enabling complete post-deployment reports.
3. Remove stale Redis checks from the health tooling, or make them conditional on Redis being part of the compose project.
4. Teach the data-check script to source credentials dynamically from the deployed environment.
