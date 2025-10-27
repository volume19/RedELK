# RedELK v3.0 - Red Team SIEM Stack

A comprehensive Red Team SIEM platform built on the Elastic Stack (Elasticsearch, Logstash, Kibana) for tracking and analyzing red team operations.

## 🚀 Features

- **Complete C2 Integration**: Full support for Cobalt Strike and PoshC2
- **Redirector Traffic Analysis**: Parse and analyze Apache, Nginx, HAProxy logs
- **Advanced Threat Detection**: 10+ detection rules for identifying analysis environments
- **GeoIP Enrichment**: Automatic geographic mapping of source IPs
- **CDN/Cloud Detection**: Identify traffic from major CDN and cloud providers
- **Automated Threat Intelligence**: Regular updates of TOR nodes, compromised IPs
- **Operational Dashboards**: Pre-built Kibana dashboards for real-time monitoring
- **Helper Scripts**: Tools for health checks, beacon management, and testing

## 📋 Requirements

- **OS**: Ubuntu 20.04, 22.04, or 24.04 LTS
- **Resources**: 4+ CPU, 8+ GB RAM, 50+ GB disk
- **Network**: Ports 80, 443, 5044, 5601, 9200 available
- **Access**: Root/sudo privileges
- **Internet**: Required for initial setup

## 🔧 Quick Installation

See **[DEPLOY.md](DEPLOY.md)** for complete deployment instructions.

### Standard Deployment
```bash
# Copy bundle to your RedELK server
scp redelk-v3-deployment.tar.gz root@YOUR_SERVER:/tmp/

# On the server
cd /tmp
tar xzf redelk-v3-deployment.tar.gz
cd DEPLOYMENT-BUNDLE
sudo bash redelk_ubuntu_deploy.sh
```

### Build from Source
```bash
# Clone repository
git clone https://github.com/outflanknl/RedELK.git
cd RedELK

# Build deployment bundle
bash create-bundle.sh

# Deploy to server
scp redelk-v3-deployment.tar.gz root@YOUR_SERVER:/tmp/
```

## 🎯 Post-Installation

### Access Kibana (after ~5 minutes)
- **URL**: `https://YOUR_SERVER_IP/`
- **Username**: `elastic`
- **Password**: `RedElk2024Secure`

### Verify Installation
```bash
sudo /opt/RedELK/scripts/redelk-health-check.sh
sudo /opt/RedELK/scripts/verify-deployment.sh
```

### Generate Test Data
```bash
# See dashboards with sample data
sudo /opt/RedELK/scripts/test-data-generator.sh
```

## 📁 What's Included

- **Deployment Bundle**: `redelk-v3-deployment.tar.gz` - Complete deployment package
- **Build Script**: `create-bundle.sh` - Rebuild bundle from source
- **Dashboard Fix**: `fix-dashboards.sh` - Retry dashboard import if needed
- **C2 Parsers**: Cobalt Strike, PoshC2, Sliver
- **Redirector Parsers**: Apache, Nginx, HAProxy
- **Detection Rules**: Sandbox, TOR, VPN, Scanner detection
- **Enrichment**: GeoIP, CDN detection, User Agent analysis
- **Helper Scripts**: Health check, beacon manager, threat feed updater
- **Dashboards**: Pre-built Kibana visualizations

## ✨ What's New in v3.0.3 (2025-10-26)

**ROOT CAUSE FIX**: Deployment script now includes Cobalt Strike parsing in main.conf

### The Real Problem (Finally Fixed!)
- **Previous versions (v3.0.1, v3.0.2)**: Deployment script created `main.conf` with NO parsing logic
- **Only basic routing** - all Cobalt Strike logs stored as unparsed raw text
- **Parsing configs existed** in `conf.d/` but were NEVER loaded by Logstash container
- **v3.0.3 Fix**: Embeds complete Cobalt Strike parser directly into `main.conf`

### Impact
- ✅ **NEW deployments work out of the box** - no hotfixes needed
- ✅ Beacon logs parsed automatically: IDs, commands, operators, hostnames
- ✅ Dashboards populate immediately with structured data
- ✅ All log types supported: beacon, events, weblog, downloads, keystrokes, screenshots
- ✅ Compatible with official RedELK Filebeat field structure

### For Existing v3.0.1/v3.0.2 Users
You need to redeploy or manually replace `/opt/RedELK/elkserver/logstash/pipelines/main.conf`

See [CHANGELOG.md](CHANGELOG.md) for complete root cause analysis.

---

## Previous Releases

### v3.0.2 (2025-10-26)
Field structure compatibility fix (incomplete - parsing still not working)

Production-hardened release with critical fixes for reliability:

### Critical Fixes
1. **Hardcoded Logstash Auth** - Eliminates environment variable resolution issues (was causing crash-loop)
2. **Logstash Healthcheck** - Checks container logs instead of unavailable API port (was exiting prematurely)
3. **Extended Timeouts** - 6min ES / 6min Logstash / 10min Kibana (works on slow hardware)
4. **Dashboard Import** - Automatic import with fail-fast error handling (prevents silent failures)
5. **Filebeat Cleanup** - Deployment scripts clean up previous installations
6. **Flexible CS Paths** - Supports multiple Cobalt Strike installation locations

### Platform Support
7. **Ubuntu 24.04 LTS** - Full compatibility with latest Ubuntu
8. **Elastic Stack 8.15.3** - Latest stable Elastic components
9. **Comprehensive Logging** - Detailed logs at /var/log/redelk_deploy.log
10. **Tested** - Verified on fast and slow hardware

See [CHANGELOG.md](CHANGELOG.md) for complete details.

## 📌 Versioning

RedELK follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`

- **Current Version**: v3.0.3 (see [VERSION](VERSION) file)
- **Version History**: [CHANGELOG.md](CHANGELOG.md)
- **Versioning Policy**: [VERSIONING.md](VERSIONING.md)

For upgrade paths and compatibility information, see [VERSIONING.md](VERSIONING.md).

## 🛡️ Security

- Elasticsearch bound to localhost only (secure by default)
- HTTPS/TLS with self-signed certificates
- Service account token authentication
- Real-time threat detection

## 🔍 Troubleshooting

### Empty Dashboards?
```bash
# Generate test data
sudo /opt/RedELK/scripts/test-data-generator.sh

# Or deploy Filebeat agents to your C2/redirectors
```

### Service Management
```bash
sudo systemctl status redelk
sudo docker logs redelk-kibana
sudo docker logs redelk-elasticsearch
```

### Complete Cleanup
```bash
cd /opt/RedELK/elkserver/docker && sudo docker compose down -v
sudo docker rm -f $(docker ps -a | grep redelk | awk '{print $1}')
sudo rm -rf /opt/RedELK
sudo systemctl disable --now redelk
```

## 📄 License

BSD 3-Clause License

## ⚠️ Disclaimer

For authorized security testing only. Users must comply with all applicable laws.