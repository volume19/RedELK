# RedELK Debugging & Plumbing Audit

## Overview
RedELK bundles a Bash-driven installer, Docker Compose stack, Logstash pipelines, and Filebeat deployment helpers that wrap Elastic 8.15 services (Elasticsearch, Logstash, Kibana, and an nginx proxy). The repository contains no RAG, LLM, or multi-agent components—everything centers on traditional SIEM plumbing.

**Overall risk: high.** Core ingestion paths currently fail because Logstash references template assets that are not shipped, the outputs authenticate with a disabled system user, and every Filebeat profile ships fields and TLS settings that do not match the pipelines they feed. Even auxiliary tooling (beacon manager, diagnostics) carries credential and privilege assumptions that break default installs.

**Systemic issues observed**
1. Logstash output wiring is stale: it points at missing template files and the wrong Elasticsearch principal, so pipelines cannot establish connections at runtime.【F:elkserver/logstash/conf.d/90-outputs.conf†L5-L78】【F:create-bundle.sh†L55-L59】
2. All Filebeat templates disagree with the pipelines on field shape and transport security, preventing any redirector or C2 data from being processed until configs are hand-edited.【F:c2servers/filebeat-cobaltstrike.yml†L14-L128】【F:redirs/filebeat-nginx.yml†L14-L42】【F:elkserver/logstash/conf.d/50-filter-c2-cobaltstrike.conf†L5-L11】【F:elkserver/logstash/conf.d/20-filter-redir-apache.conf†L5-L45】【F:elkserver/logstash/conf.d/10-input-filebeat.conf†L5-L12】
3. Operational scripts assume outdated credentials or elevated shells, so the shipped diagnostics fail once the new installer generates fresh secrets.【F:scripts/redelk-beacon-manager.sh†L8-L26】【F:scripts/check-redelk-data.sh†L55-L58】

## Findings by category

### Configuration / Environment / Build
1. **Critical – Missing Logstash template payloads and wrong paths.** Logstash outputs still load `/usr/share/logstash/config/templates/*.json`, yet the bundle only packages three `*-template.json` files under `elasticsearch/index-templates`, so startup will fail with `ENOENT` while trying to install templates that are absent.【F:elkserver/logstash/conf.d/90-outputs.conf†L5-L78】【F:create-bundle.sh†L55-L59】  
   *Impact:* Logstash will refuse to create the pipelines, leaving Beats events undelivered.  
   *Fix:* Either ship the expected templates at the referenced paths or remove the legacy `template` directives in favor of the `_index_template` API upload already performed during deployment.
2. **Critical – Logstash authenticates as `logstash_system`.** Every Elasticsearch output uses the built-in `logstash_system` user but the deployment never assigns that user a password—only the `elastic` superuser is configured in `.env` and Kibana.【F:elkserver/logstash/conf.d/90-outputs.conf†L9-L75】【F:redelk_ubuntu_deploy.sh†L440-L614】  
   *Impact:* All write attempts receive 401 errors, preventing index creation.  
   *Fix:* Create a service account or dedicated ingest user during deployment and update the outputs (and `.env`) to use those credentials.
3. **High – Beats TLS is disabled while the server enforces it.** The Beats input requires TLS certificates, but every Filebeat profile ships with `ssl.enabled: false`, guaranteeing handshake failures.【F:elkserver/logstash/conf.d/10-input-filebeat.conf†L5-L12】【F:c2servers/filebeat-cobaltstrike.yml†L124-L128】【F:redirs/filebeat-nginx.yml†L38-L42】  
   *Impact:* Agents will log `x509: certificate required` errors and never connect.  
   *Fix:* Enable TLS in the Filebeat configs, point them at the shipped certificates, and update the deployment helpers to install the CA before starting the service.
4. **Medium – Placeholder Beats hosts never get substituted.** Both deployment helpers simply copy `filebeat-*.yml` into `/etc/filebeat` without asking for the RedELK endpoint, leaving `REDELK_SERVER_IP` untouched.【F:c2servers/filebeat-cobaltstrike.yml†L124-L127】【F:redirs/filebeat-nginx.yml†L38-L41】【F:scripts/deploy-filebeat-c2.sh†L193-L200】【F:scripts/deploy-filebeat-redir.sh†L182-L199】  
   *Impact:* Filebeat exits immediately because it cannot resolve the placeholder host.  
   *Fix:* Prompt for or accept an argument/environment variable with the collector address and rewrite the host list before enabling the service.

### Data Models / DB / API Contracts
1. **Critical – C2 Filebeat fields never reach the filters.** The Cobalt Strike profile keeps `fields_under_root: false`, producing `fields.infra.log.type`, while the Logstash filter expects `infra.log.type` and `c2.program` at the top level, so the conditional guard never matches and the C2 parser is skipped entirely.【F:c2servers/filebeat-cobaltstrike.yml†L14-L23】【F:elkserver/logstash/conf.d/50-filter-c2-cobaltstrike.conf†L5-L11】  
   *Impact:* Beacon logs pass through unparsed, depriving dashboards and detections of structured data.  
   *Fix:* Either set `fields_under_root: true` in the Filebeat configs or update the pipelines to read from the `fields.*` namespace.
2. **Critical – Redirector feeds use different field names.** Redirector Filebeat configs emit `fields.infra.log.type` and `fields.redir.program`, yet the Apache/Nginx/Haproxy filters check `fields.infralogtype`/`fields.redirprogram`, so no redirector records enter the filter logic.【F:redirs/filebeat-nginx.yml†L14-L36】【F:elkserver/logstash/conf.d/20-filter-redir-apache.conf†L5-L45】  
   *Impact:* Redirector traffic stays raw, breaking enrichment, CDN detection, and alarm generation.  
   *Fix:* Align the Filebeat fields with the expected flat keys or adjust the filters to traverse the nested structure.
3. **High – Threat detection looks for `fields.logtype` that never exists.** The detection rules branch on `[fields][logtype] == "rtops"`, but neither the Filebeat profiles nor the C2 filters populate that property (only `infra.log.type` exists).【F:c2servers/filebeat-cobaltstrike.yml†L14-L23】【F:elkserver/logstash/conf.d/70-detection-threats.conf†L90-L153】  
   *Impact:* No C2 detections ever trigger, even when the underlying events arrive.  
   *Fix:* Set `fields.logtype` in the Filebeat emitter or switch the detection logic to the same key used by the filters (e.g., `infra.log_type`).

### Services / Jobs / Messaging
1. **Critical – Beats output credentials invalid.** Because the outputs authenticate as `logstash_system` with `${ELASTIC_PASSWORD}`, Logstash continuously retries failed writes and never acknowledges Beat batches.【F:elkserver/logstash/conf.d/90-outputs.conf†L9-L75】  
   *Impact:* Beats backpressure builds, eventually choking log shipping.  
   *Fix:* Provision correct credentials (service account or API key) and store them in `.env` for both Logstash and Beats to consume.

### Logging / Observability / Error Handling
1. **High – Beacon manager defaults to `changeme`.** The CLI still assumes the pre-8.x bootstrap password and ignores the `.env` that deployment generates, so every query fails unless operators export `ELASTIC_PASSWORD` manually.【F:scripts/redelk-beacon-manager.sh†L8-L26】  
   *Impact:* Incident responders cannot use the shipped tooling without reverse-engineering credentials.  
   *Fix:* Mirror the credential-loading helper used by the other scripts (read `elkserver/.env` and fall back to the default only if missing).
2. **Medium – Data checker hard-codes `sudo netstat`.** The diagnostics script runs `sudo netstat`, which prompts for a password or fails outright when executed as a non-root operator, even though `ss` is already used as a fallback.【F:scripts/check-redelk-data.sh†L55-L61】  
   *Impact:* The check hangs or exits early during routine health reviews.  
   *Fix:* Prefer `ss` without `sudo`, or detect privilege escalation requirements before invoking `netstat`.

## Prioritized remediation plan
1. **Fix Logstash template packaging and credentials** – Update `elkserver/logstash/conf.d/90-outputs.conf`, deployment scripts, and bundle contents so templates exist and outputs authenticate with a valid user or API key; validate by re-running `docker compose up` and watching for pipeline readiness.  
2. **Enable TLS and host substitution in Filebeat configs** – Patch `c2servers/*.yml`, `redirs/*.yml`, and the `deploy-filebeat-*.sh` helpers to inject the RedELK host and certificate paths; verify with `filebeat test output`.  
3. **Align Filebeat field structure with Logstash filters** – Decide on either nested (`fields.*`) or root-level (`infra.*`, `c2.*`) fields and update both the Filebeat configs and the corresponding filters; confirm by shipping sample logs and checking structured fields in Elasticsearch.  
4. **Repair redirector pipeline guards** – Adjust the Apache/Nginx/Haproxy filters to match the new field naming scheme and ensure CDN/threat enrichments fire; validate via the health scripts and Logstash logs.  
5. **Correct detection rules to use real field names** – Modify `70-detection-threats.conf` to test the same keys emitted by the filters (e.g., `infra.log_type`) and confirm alarms populate the `alarms-*` index after replaying sample events.  
6. **Teach operational tooling to read `.env` credentials** – Extend `scripts/redelk-beacon-manager.sh`, `scripts/check-redelk-data.sh`, and similar utilities to load passwords the same way as `verify-deployment.sh`; test by running each script on a fresh install.  
7. **Remove hard-coded `sudo netstat` invocation** – Update `scripts/check-redelk-data.sh` to prefer `ss` without privilege escalation; rerun the script as a non-root user to confirm it completes.  
8. **Re-run end-to-end health checks** – After the above fixes, rerun `scripts/verify-deployment.sh`, `scripts/redelk-health-check.sh`, and ingest sample data to ensure no regressions in dashboards or alarms.  
9. **Document new credential flows** – Update operator docs and `.env` handling guidance so future tooling changes reuse the standardized credential-loading helpers; spot-check by reviewing README sections referenced during deployment.  
10. **Add automated smoke tests** – Introduce CI or local scripts that spin up the compose stack, push synthetic Beats data, and assert index creation so future plumbing regressions are caught before release.
