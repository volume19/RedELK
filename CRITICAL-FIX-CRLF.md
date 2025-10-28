# CRITICAL FIX: Logstash Config Validation Failure

**Date**: 2025-10-27
**Version**: v3.0.7 → v3.0.8
**Severity**: CRITICAL - Deployment breaking issue

---

## Root Cause Analysis

### The Problem

Logstash validation was failing with a **regex parsing error** at line 61 of `20-filter-redir-apache.conf`:

```
[FATAL][logstash.runner] The given configuration is invalid.
Reason: Expected one of [ \t\r\n], "#", "and", "or", "xor", "nand", "{"
at line 61, column 108 (byte 2321)
```

The regex pattern appeared truncated in validation output:
```ruby
if [user_agent.original] =~ /curl|wget|python|powershell|nmap|nikto|sqlmap|dirbuster|burp|zap|acunetix/
```

Missing: `/i {` at the end

### The Root Cause

**ALL 11 Logstash config files had Windows CRLF line terminators** instead of Unix LF.

```bash
$ file elkserver/logstash/conf.d/20-filter-redir-apache.conf
ASCII text, with very long lines (625), with CRLF line terminators
                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

Logstash (running in Linux Docker container) expects Unix LF line endings. The CRLF characters (`\r\n`) were confusing the parser, causing it to misinterpret regex patterns and fail validation.

### Why This Happened

- Files were edited on Windows, which uses CRLF by default
- `create-bundle.sh` was **NOT** normalizing line endings for `.conf` files
- Only the deployment script and helper scripts had line ending normalization
- Docker validation showed the symptom (truncated regex) but not the root cause (CRLF)

---

## The Fix

### 1. Fixed All 11 Config Files (Immediate)

```bash
for f in elkserver/logstash/conf.d/*.conf; do
    sed -i 's/\r$//' "$f"
done
```

**Affected files**:
- 10-input-filebeat.conf
- 20-filter-redir-apache.conf
- 21-filter-redir-nginx.conf
- 22-filter-redir-haproxy.conf
- 50-filter-c2-cobaltstrike.conf
- 51-filter-c2-poshc2.conf
- 60-enrich-geoip.conf
- 61-enrich-cdn.conf
- 62-enrich-useragent.conf
- 70-detection-threats.conf
- 90-outputs.conf

### 2. Updated Bundle Creation Script (Permanent)

Modified `create-bundle.sh` to normalize line endings for ALL file types during bundle creation:

**Before**:
```bash
# Logstash configs
if ls elkserver/logstash/conf.d/*.conf >/dev/null 2>&1; then
    cp elkserver/logstash/conf.d/*.conf "$BUNDLE_DIR/" 2>/dev/null
    echo "  ✓ Logstash configs"
fi
```

**After**:
```bash
# Logstash configs (CRITICAL: normalize line endings for Docker compatibility)
if ls elkserver/logstash/conf.d/*.conf >/dev/null 2>&1; then
    for conf in elkserver/logstash/conf.d/*.conf; do
        sed 's/\r$//' "$conf" > "$BUNDLE_DIR/$(basename "$conf")"
    done
    CONF_COUNT=$(ls elkserver/logstash/conf.d/*.conf 2>/dev/null | wc -l)
    echo "  ✓ Logstash configs ($CONF_COUNT files, line endings fixed)"
fi
```

Applied same fix to:
- Elasticsearch templates (*.json)
- Threat feeds (*.txt)
- Kibana dashboards (*.ndjson)
- Filebeat configs (*.yml)

### 3. Added Verbose Logstash Logging

Updated `redelk_ubuntu_deploy.sh` to show **real-time Logstash logs** during startup:

**Before**: Silent dots with timeout
```bash
echo -n "[INFO] Waiting for Logstash to be ready (checking logs for port 5044)"
for ((i=1;i<=120;i++)); do
    if docker logs redelk-logstash 2>&1 | grep -q "Starting server on port: 5044"; then
        ok=true; break
    fi
    sleep 3; echo -n "."
done
```

**After**: Live log streaming
```bash
echo "[INFO] Monitoring Logstash startup (verbose mode)..."
echo "[INFO] Showing real-time Logstash logs during startup"

# Start log streaming in background
docker logs -f redelk-logstash 2>&1 &
log_pid=$!

# Wait for successful startup
for ((i=1;i<=120;i++)); do
    if docker logs redelk-logstash 2>&1 | grep -q "Starting server on port: 5044"; then
        ok=true; break
    fi
    sleep 3
done

# Stop log streaming
kill $log_pid 2>/dev/null || true
```

This ensures any future config errors will be **immediately visible** instead of silently spinning.

---

## Verification

### Bundle Self-Test Results

```
======================================================================
                         SELF-TEST SUMMARY
======================================================================
Logstash Configs:      11/11 ✓
ES Templates:          3/3   ✓
Kibana Dashboards:     1/1   ✓
Critical Scripts:      2/2   ✓
C2 Filebeat Configs:   2     ✓
Redir Filebeat Configs: 3    ✓

RESULT: PASS - Bundle structure is valid
======================================================================
```

### Line Ending Verification

```bash
$ file DEPLOYMENT-BUNDLE/20-filter-redir-apache.conf
ASCII text, with very long lines (625)
# ✓ No "CRLF" mentioned = Unix LF line endings
```

---

## Deployment Status

**New Bundle**: `redelk-v3-deployment.tar.gz` (48KB, was 45KB)

**Changes**:
1. All config files now have Unix LF line endings
2. Bundle creation automatically normalizes all text files
3. Deployment script provides verbose Logstash output
4. Self-test validates bundle structure before deployment

**Expected Behavior**:
- Logstash validation should now **PASS** without errors
- Logstash should start successfully and listen on port 5044
- Real-time logs will show exact startup progress
- Any future config errors will be immediately visible

---

## Lessons Learned

1. **Cross-platform line endings are critical** for Docker deployments
   - Windows CRLF (\r\n) breaks Linux parsers
   - Always normalize to Unix LF (\n) during packaging

2. **Validation feedback must be verbose** for debugging
   - Silent failures waste time
   - Real-time logs catch issues immediately

3. **Every file type must be normalized**
   - .conf, .json, .yml, .txt, .ndjson
   - No assumptions about file origins

4. **Self-tests prevent deployment failures**
   - Offline validation catches issues before deployment
   - Structure checks ensure completeness

---

## Next Steps

1. **Deploy new bundle** to test Logstash startup
2. **Verify Logstash successfully starts** and listens on port 5044
3. **Confirm validation passes** without warnings
4. **Run post-flight checks** to ensure all services operational

If deployment succeeds:
- Tag as `v3.0.8` with message: "CRITICAL FIX - Line endings causing Logstash validation failure"
- Update VERSION file
- Document in CHANGELOG.md
