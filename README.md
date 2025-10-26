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

### Option 1: Diagnostic Deployment (Recommended for Testing)
```bash
# For quick testing or troubleshooting
wget https://raw.githubusercontent.com/volume19/RedELK/master/DIAGNOSE-AND-FIX.sh
sudo bash DIAGNOSE-AND-FIX.sh
```
**Best for**: Quick testing, troubleshooting, development environments

### Option 2: Full Production Deployment
```bash
# Clone repository
git clone https://github.com/volume19/RedELK.git
cd RedELK

# Use the full deployment script
sudo bash redelk_ubuntu_deploy.sh
```
**Best for**: Production deployments with full features and monitoring

### Option 3: Build Deployment Bundle
```bash
# Clone and create deployment bundle
git clone https://github.com/volume19/RedELK.git
cd RedELK
./create-bundle.sh  # Creates redelk-v3-deployment.tar.gz
```
**Best for**: Offline deployments or distributing to multiple servers

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

- **Deployment Scripts**:
  - `DIAGNOSE-AND-FIX.sh` - Fast diagnostic deployment with all production fixes
  - `redelk_ubuntu_deploy.sh` - Full production deployment with complete feature set
  - `create-bundle.sh` - Bundle generator for offline deployments
- **C2 Parsers**: Cobalt Strike, PoshC2
- **Redirector Parsers**: Apache, Nginx, HAProxy
- **Detection Rules**: Sandbox, TOR, VPN, Scanner detection
- **Enrichment**: GeoIP, CDN detection, User Agent analysis
- **Helper Scripts**: Health check, beacon manager, threat feed updater
- **Dashboards**: Pre-built Kibana visualizations

## ✨ Recent Improvements (v3.0.1)

The `DIAGNOSE-AND-FIX.sh` script includes all production-ready fixes:

1. **Kibana Service Account Token** - Uses proper authentication instead of elastic user
2. **Kibana Health Checks** - Real health-gating prevents 502 errors
3. **Logstash Pipeline Syntax** - Fixed configuration format for proper startup
4. **Nginx Dependency Fix** - Allows Nginx to start while Kibana initializes
5. **Nginx Configuration** - Clean, validated config with proper proxy settings
6. **Bind-Mount ES Data** - Uses deterministic paths for easier management
7. **Readiness Checks** - Replaces fixed sleeps with real service checks
8. **Token Management** - Avoids 409 conflicts with unnamed tokens
9. **File Permissions** - Ensures Kibana can read its configuration
10. **ES Prerequisites** - Maintains proper vm.max_map_count and heap settings

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