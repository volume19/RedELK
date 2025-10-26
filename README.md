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

### Option 1: Use the Deployment Bundle (Recommended)
```bash
# Copy the REDELK-DEPLOYMENT-BUNDLE folder to your server
scp -r REDELK-DEPLOYMENT-BUNDLE/ user@server:/tmp/

# Run deployment
cd /tmp/REDELK-DEPLOYMENT-BUNDLE
sudo bash DEPLOY-ME.sh
```

### Option 2: Direct Install
```bash
# Clone and run
git clone https://github.com/yourusername/RedELK.git
cd RedELK
sudo bash redelk_ubuntu_deploy.sh
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

- **Main Script**: One-command deployment
- **C2 Parsers**: Cobalt Strike, PoshC2
- **Redirector Parsers**: Apache, Nginx, HAProxy
- **Detection Rules**: Sandbox, TOR, VPN, Scanner detection
- **Enrichment**: GeoIP, CDN detection, User Agent analysis
- **Helper Scripts**: Health check, beacon manager, threat feed updater
- **Dashboards**: Pre-built Kibana visualizations

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