# RedELK Debugging Audit

## Overview
This report captures the most impactful runtime, configuration, and tooling risks identified during a code-level audit of the current RedELK repository. Findings are grouped by category, with the affected components and recommended remediation strategies noted for each item.

## Resolution summary
- **Logstash threat-feed lookups:** Pipelines now reference the feed directory mounted at `/usr/share/logstash/config/threat-feeds`, restoring CDN and TOR detections after the deployment layout refactor.
- **Operational tooling resiliency:** Verification and health-check scripts manage failures internally, report cumulative results, and continue running even when individual checks fail.
- **Credential sourcing:** Operational scripts load the Elasticsearch password from the deployment `.env`, honoring operator overrides instead of hard-coded defaults.
- **Retired Redis artifacts:** Health monitoring no longer alerts on the deprecated Redis container or port.

## Logstash pipeline configuration mismatches
- **Threat feed path drift (resolved):** The pipeline that detects CDN traffic now reads from `/usr/share/logstash/config/threat-feeds/cdn-ip-lists.txt`, matching the deployed mount so `cidr` lookups receive the updated feed files.【F:elkserver/logstash/conf.d/61-enrich-cdn.conf†L1-L70】【F:redelk_ubuntu_deploy.sh†L520-L637】
- **Alarm translate dictionaries (resolved):** TOR detection lookups reference `/usr/share/logstash/config/threat-feeds/tor-exit-nodes.txt`, aligned with the relocated threat feeds and restoring translate enrichment.【F:elkserver/logstash/conf.d/70-detection-threats.conf†L1-L87】【F:redelk_ubuntu_deploy.sh†L520-L637】

## Operational tooling stability
- **Verification script exits prematurely (resolved):** `scripts/verify-deployment.sh` now retains `set -uo pipefail`, tracks check results internally, and continues execution even when individual checks fail so operators receive a full report.【F:scripts/verify-deployment.sh†L1-L312】
- **Health check script aborts early (resolved):** The health check utility mirrors the failure tracking approach, allowing it to finish with summarized warnings and failures instead of stopping at the first error.【F:scripts/redelk-health-check.sh†L1-L180】

## Monitoring coverage accuracy
- **Redis references in health tooling (resolved):** Redis container and port checks were removed so the health tooling reflects the current docker-compose stack.【F:scripts/redelk-health-check.sh†L54-L123】【F:redelk_ubuntu_deploy.sh†L520-L637】

## Configuration consistency
- **Hard-coded Elasticsearch credentials (resolved):** Operational diagnostics and health tooling source credentials from the deployment `.env`, honoring operator overrides instead of relying on a hard-coded password.【F:scripts/check-redelk-data.sh†L1-L70】【F:scripts/redelk-health-check.sh†L1-L180】【F:scripts/verify-deployment.sh†L1-L312】【F:redelk_ubuntu_deploy.sh†L432-L452】

## Follow-up recommendations
1. Maintain parity between bundle layouts and Logstash pipeline paths whenever threat-feed assets move.
2. Periodically extend the verification and health-check coverage to include any new services introduced to the stack.
3. Document retired infrastructure components alongside tooling updates to prevent stale checks from reappearing.
4. Encourage operators to manage credentials through the deployment `.env` and rotate passwords as part of regular maintenance.
