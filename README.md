# RedELK v3.0.6 - Red Team SIEM Stack

A comprehensive Red Team SIEM platform built on the Elastic Stack (Elasticsearch, Logstash, Kibana) for tracking and analyzing red team operations.

## 🆕 v3.0.6 Updates

**Critical Field Structure Fix**:
- ✅ Filebeat configs now use nested field structure (`infra.log.type`, `c2.program`)
- ✅ Deployment script automatically handles conflicting Logstash configurations
- ✅ Dashboards populate automatically without manual intervention
- ✅ Generated deployment packages ready to use (no manual editing required)

**Visual Enhancements**:
- ✅ Enhanced ASCII art banners with Unicode box-drawing
- ✅ Color-coded output (errors, success, warnings, info)
- ✅ Progress bars and spinner animations
- ✅ Clear phase separation and visual feedback

**Complete Cleanup**:
- ✅ Removes ALL traces of previous installations
- ✅ Backs up configs before removal
- ✅ Cleans Docker containers, volumes, networks
- ✅ Removes old logs, registries, and temp files

**What This Fixes**: Resolves "empty dashboards despite data ingestion" issue caused by field structure mismatch between Filebeat and Logstash.

---

## 🚀 Features

- **Complete C2 Integration**: Full support for Cobalt Strike and PoshC2
- **Redirector Traffic Analysis**: Parse and analyze Apache, Nginx, HAProxy logs
- **Advanced Threat Detection**: 10+ detection rules for identifying analysis environments
- **GeoIP Enrichment**: Automatic geographic mapping of source IPs
- **CDN/Cloud Detection**: Identify traffic from major CDN and cloud providers
- **Automated Threat Intelligence**: Regular updates of TOR nodes, compromised IPs
- **Operational Dashboards**: Pre-built Kibana dashboards for real-time monitoring
- **Helper Scripts**: Tools for health checks, beacon management, and testing

---

## 📋 Requirements

- **OS**: Ubuntu 20.04, 22.04, or 24.04 LTS
- **Resources**: 4+ CPU, 8+ GB RAM, 50+ GB disk
- **Network**: Ports 80, 443, 5044 available
- **Access**: Root/sudo privileges
- **Internet**: Required for initial setup

---

## 🔧 Quick Installation

### Deploy RedELK Server

```bash
# Copy bundle to your RedELK server
scp redelk-v3-deployment.tar.gz root@YOUR_SERVER:/tmp/

# On the server
cd /tmp
tar xzf redelk-v3-deployment.tar.gz
cd DEPLOYMENT-BUNDLE
sudo bash install-redelk.sh
```

### Deploy to C2 Servers

```bash
# From RedELK server (after deployment completes)
scp /tmp/c2servers.tgz root@C2_SERVER:/tmp/

# On C2 server
cd /tmp && tar xzf c2servers.tgz && cd c2package
sudo bash deploy-filebeat-c2.sh
```

### Deploy to Redirectors

```bash
# From RedELK server
scp /tmp/redirs.tgz root@REDIRECTOR:/tmp/

# On redirector
cd /tmp && tar xzf redirs.tgz && cd redirpackage
sudo bash deploy-filebeat-redir.sh
```

---

## 📚 Documentation

- **DEPLOY-NOW.txt** - Quick reference deployment commands
- **ENHANCED-DEPLOYMENT-GUIDE.md** - Complete deployment guide with visual examples
- **FINAL-STATUS.md** - Implementation summary and verification
- **modernize-redelk.plan.md** - Technical repair plan and diagnostic commands
- **CHANGELOG.md** - Version history

---

## 🔍 Verification

After deployment, verify dashboards work:

```bash
# Check data exists
curl -s -u elastic:RedElk2024Secure "http://localhost:9200/rtops-*/_count" | jq '.count'

# Verify nested field structure
curl -s -u elastic:RedElk2024Secure "http://localhost:9200/rtops-*/_search?size=1" \
  | jq '.hits.hits[0]._source | has("infra")'
# Should return: true

# Access Kibana
https://YOUR_SERVER_IP/
Username: elastic
Password: RedElk2024Secure

# Navigate: Analytics → Dashboards → RedELK Main Overview
# Should see populated visualizations ✅
```

---

## 🛡️ Security Checklist

Before production use:

- [ ] Change default password: `ELASTIC_PASSWORD` in deployment script
- [ ] Configure firewall rules (allow only necessary IPs on port 5044)
- [ ] Enable SSL/TLS for Filebeat → Logstash if on public networks
- [ ] Review and customize detection rules
- [ ] Set up Elasticsearch snapshots for backup
- [ ] Configure index lifecycle management (ILM) for retention
- [ ] Review helper scripts for your environment

---

## 📊 What's New in v3.0.6

| Feature | Status |
|---------|--------|
| Nested field structure | ✅ Fixed |
| Auto-cleanup previous installs | ✅ Added |
| Enhanced visual UI | ✅ Added |
| Progress bars/spinners | ✅ Added |
| Color-coded output | ✅ Added |
| Conflicting config handler | ✅ Added |
| Dashboard auto-population | ✅ Fixed |
| Zero manual edits required | ✅ Achieved |

---

## 🔧 Management Commands

```bash
# Service management
systemctl status redelk
systemctl restart redelk
systemctl stop redelk

# View logs
docker logs redelk-elasticsearch
docker logs redelk-logstash
docker logs redelk-kibana
docker logs redelk-nginx

# Health check
bash /opt/RedELK/scripts/redelk-health-check.sh

# Verify deployment
bash /opt/RedELK/scripts/verify-deployment.sh

# Check data ingestion
bash /opt/RedELK/scripts/check-redelk-data.sh
```

---

## 🆘 Troubleshooting

### Dashboards Still Empty?

```bash
# 1. Check data exists
curl -s -u elastic:RedElk2024Secure "http://localhost:9200/rtops-*/_count" | jq

# 2. Check field structure
curl -s -u elastic:RedElk2024Secure "http://localhost:9200/rtops-*/_search?size=1" \
  | jq '.hits.hits[0]._source | keys'
# Should include: "infra", "c2" or "redir"

# 3. Check Filebeat on C2/redirector
ssh root@C2_SERVER "systemctl status filebeat"
ssh root@C2_SERVER "journalctl -u filebeat -n 50"

# 4. Check Logstash pipeline
curl -s http://localhost:9600/_node/stats/pipelines?pretty | jq '.pipelines.main.events'
```

See `modernize-redelk.plan.md` for complete diagnostic commands.

---

## 📦 Project Structure

```
RedELK/
├── redelk_ubuntu_deploy.sh       Main deployment script (enhanced)
├── create-bundle.sh               Bundle creation script
├── redelk-v3-deployment.tar.gz   Ready-to-deploy bundle
├── VERSION                        Version number (3.0.6)
├── README.md                      This file
├── DEPLOY-NOW.txt                 Quick deploy reference
├── ENHANCED-DEPLOYMENT-GUIDE.md   Complete deployment guide
├── FINAL-STATUS.md                Implementation summary
├── modernize-redelk.plan.md       Technical repair plan
├── CHANGELOG.md                   Version history
├── DEPLOY.md                      Legacy deployment docs
├── c2servers/                     C2 Filebeat templates (nested fields)
│   ├── filebeat-cobaltstrike.yml
│   ├── filebeat-poshc2.yml
│   └── README.md
├── redirs/                        Redirector Filebeat templates (nested fields)
│   ├── filebeat-nginx.yml
│   ├── filebeat-apache.yml
│   ├── filebeat-haproxy.yml
│   └── README.md
├── elkserver/                     ELK stack configurations
│   ├── elasticsearch/
│   │   └── index-templates/       Index mapping templates
│   ├── logstash/
│   │   ├── conf.d/                Logstash pipeline configs
│   │   └── threat-feeds/          Threat intelligence feeds
│   └── kibana/
│       └── dashboards/            Kibana saved objects
└── scripts/                       Helper and deployment scripts
    ├── deploy-filebeat-c2.sh      C2 agent installer (enhanced)
    ├── deploy-filebeat-redir.sh   Redirector agent installer (enhanced)
    ├── redelk-health-check.sh     Health monitoring
    ├── verify-deployment.sh       Post-deploy verification
    ├── check-redelk-data.sh       Data ingestion checker
    ├── test-data-generator.sh     Test data generator
    ├── update-threat-feeds.sh     Threat feed updater
    └── redelk-beacon-manager.sh   Beacon management
```

---

## 🎯 Production Ready

The bundle `redelk-v3-deployment.tar.gz` is **PRODUCTION READY** with:
- All technical fixes implemented (nested fields, conflict handling)
- Enhanced visual UI with progress indicators
- Complete cleanup of previous installations
- Auto-detection and validation
- Beautiful ASCII art and color coding
- Zero manual configuration required

**Deploy now!** See `DEPLOY-NOW.txt` for quick commands.

---

## 📄 License

Red Teaming & Security Operations

## 🤝 Credits

Based on RedELK by Outflank (https://github.com/outflanknl/RedELK)
Enhanced for v3.0.6 with nested field structure and visual improvements.
