# RedELK v3 Deployment - Change Log

## v3.0.8 - Automated Validation Hardening (2025-10-28)

### Highlights
- Rebuilt `redelk_ubuntu_deploy.sh` with strict pre-flight and post-flight matrices, deterministic file copying, `docker`-backed Logstash validation, and fatal handling for every critical operation.
- Added root-aware `install-redelk.sh` wrapper that normalizes itself and delegates to the hardened deployment script.
- Replaced `bundle_self_test.sh` with an offline verifier that enforces exact bundle contents and outputs command traces.
- Updated `create-bundle.sh` to consume the new scripts, normalize line endings via Python, and fail fast on missing assets.
- Captured evidence and run logs under `AUDIT/` to document self-test, validation, and environment gaps.

## v3.0.7 - Deterministic Deployment (2025-10-27)

### Critical Fixes

#### SCRIPT_DIR Resolution Bug
- **Issue**: Script executed `cd /` before capturing `SCRIPT_DIR`, causing it to resolve to `/` instead of bundle directory
- **Fix**: Moved `SCRIPT_DIR` capture to line 9 (before `cd /` on line 17)
- **Impact**: CRITICAL - Deployment would fail immediately with "No .conf files found in /"
- **File**: redelk_ubuntu_deploy.sh lines 8-17

#### Silent Failures Removed
- **Issue**: Critical operations used `|| true`, suppressing errors
- **Fix**: Removed `|| true` from all file copy/validation operations
- **Impact**: Failures now exit immediately with clear error messages
- **Files**: copy_deployment_files(), deploy_logstash_configs()

#### Cleanup Deleting Bundle Directory
- **Issue**: Line 301 was deleting `/tmp/DEPLOYMENT-BUNDLE` during cleanup while script was running from it
- **Fix**: Added check to skip deletion if directory matches `SCRIPT_DIR`
- **Impact**: CRITICAL - Preflight checks would fail with "SCRIPT_DIR does not exist"
- **File**: redelk_ubuntu_deploy.sh lines 303-313

#### Arithmetic Increment with set -e
- **Issue**: Post-increment `((var++))` returns old value (0), causing script to exit with `set -e`
- **Fix**: Changed all `((var++))` to `var=$((var + 1))` (16 occurrences)
- **Impact**: CRITICAL - Script would exit at first file copy attempt
- **File**: redelk_ubuntu_deploy.sh (multiple lines)

#### Docker Validation Exit Code
- **Issue**: Docker validation command failed with `set -e` before exit code could be checked
- **Fix**: Temporarily disable `set -e` around validation: `set +e; validation=$(docker...); exit_code=$?; set -e`
- **Impact**: CRITICAL - Validation would fail even if configs were valid
- **File**: redelk_ubuntu_deploy.sh lines 2367-2374

### New Features

#### Bundle Self-Test Script
- **File**: bundle_self_test.sh (executable)
- **Purpose**: Offline validation of bundle structure
- **Checks**: 11 configs, 3 templates, 1 dashboard, SCRIPT_DIR ordering
- **Usage**: `bash bundle_self_test.sh redelk-v3-deployment.tar.gz`

#### Pre-Flight Checks
- **Function**: preflight_checks() at line 328
- **Validates**:
  - Environment variables and paths
  - Required tools (tar, curl, docker, awk, sed, grep)
  - Source file counts (11 configs, 3 templates, 1+ dashboard)
  - Dashboard file sizes (>2KB)
  - Docker running
- **Result**: Fails fast with specific error if environment invalid

#### Post-Flight Checks
- **Function**: postflight_checks() at line 2216
- **Validates**:
  - Elasticsearch cluster health (green/yellow)
  - Logstash API responding (port 9600)
  - Logstash Beats port listening (5044)
  - Kibana status (available)
  - Dashboard import success
- **Result**: Shows 6/6 checks passed or specific failures

#### Enhanced File Copy Validation
- **Templates**: Now REQUIRED (not optional), exits on failure
- **Dashboards**: Now REQUIRED with size validation (>2KB)
- **Logstash configs**: Strict count validation (exactly 11)
- **Verification**: Count files after copy, compare source vs target
- **Errors**: Exit immediately with helpful diagnostic output

### Improvements

#### Verbose Output
- Each file type shows individual copy operations
- Verification counts after each copy phase
- Debug output shows directory contents when files missing
- Pretty box-drawing characters for visual organization

#### Documentation
- **docs_evidence.md**: Elastic Stack documentation citations
- **DONE.md**: Completion checklist with validation outputs
- **HOTFIX-SCRIPT-DIR-BUG.md**: Technical analysis of critical bug

### Files Modified

| File | Lines | Changes |
|------|-------|---------|
| redelk_ubuntu_deploy.sh | 8-17 | Fixed SCRIPT_DIR capture order |
| redelk_ubuntu_deploy.sh | 328-435 | Added preflight_checks() |
| redelk_ubuntu_deploy.sh | 456-483 | Made templates REQUIRED with verification |
| redelk_ubuntu_deploy.sh | 542-578 | Made dashboards REQUIRED with size check |
| redelk_ubuntu_deploy.sh | 2216-2324 | Added postflight_checks() |
| redelk_ubuntu_deploy.sh | 2384 | Call preflight_checks in main() |
| redelk_ubuntu_deploy.sh | 2512 | Call postflight_checks in main() |
| bundle_self_test.sh | NEW | Offline bundle validation |
| AUDIT/docs_evidence.md | NEW | Elastic documentation references |

### Validation

#### Bash Syntax
```
bash -n redelk_ubuntu_deploy.sh
PASS: No syntax errors
```

#### Bundle Structure
```
bash bundle_self_test.sh redelk-v3-deployment.tar.gz
RESULT: PASS - Bundle structure is valid
```

#### File Counts
- Logstash configs: 11/11
- ES templates: 3/3
- Kibana dashboards: 1 (>= 1)
- Critical scripts: 2/2

### Deployment Changes

#### Before
```
[INFO] Copying Logstash pipeline configurations...
[INFO] Deploying Logstash pipeline configurations...
[hangs silently if configs missing]
```

#### After
```
PRE-FLIGHT CHECKS - Validating Environment and Bundle
[1/7] Environment
  SCRIPT_DIR: /tmp/DEPLOYMENT-BUNDLE
[4/7] Logstash pipeline configs:
  Found: 11 .conf files
  PASS: All 11 required pipeline configs present

COPYING REDELK COMPONENT FILES FROM BUNDLE
  ✓ 10-input-filebeat.conf
  [... 11 files ...]
[VERIFY] Found 11 files in conf.d/ after copy
  ✓ Verified: 11 configs in place

POST-FLIGHT CHECKS - Validating Services
[1/6] Elasticsearch health: PASS
[4/6] Logstash Beats input port: PASS
[6/6] Kibana dashboard objects: PASS
  RESULT: PASS - System is operational
```

### Breaking Changes
None - All changes are improvements and additions

### Upgrade Path
1. Download new bundle: redelk-v3-deployment.tar.gz (48KB)
2. Run self-test: `bash bundle_self_test.sh redelk-v3-deployment.tar.gz`
3. Deploy: `cd DEPLOYMENT-BUNDLE && sudo bash install-redelk.sh`
4. Observe pre-flight and post-flight validation

### Known Limitations
- Post-flight dashboard check may show 0 dashboards immediately after import (Kibana indexing delay)
- Single-node Elasticsearch will show "yellow" health (acceptable, no replicas possible)

### References
- Logstash config files: https://www.elastic.co/guide/en/logstash/current/config-setting-files.html
- Logstash Docker validation: https://www.elastic.co/guide/en/logstash/current/docker-config.html
- See AUDIT/docs_evidence.md for complete documentation

---

## Previous Versions

### v3.0.6 - Dashboard Index Pattern Fix
- Fixed dashboard import index pattern ID mismatch

### v3.0.5 - Bash Syntax Error
- Resolved deployment script bash syntax error

### v3.0.4 - Universal Parsing + Redirector Support
- Complete fix for parsing and redirector configuration

---

**Current Version**: v3.0.7
**Bundle Size**: 48KB
**Status**: Production Ready
