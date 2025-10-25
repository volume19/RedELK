# RedELK v3.0 - Quick Deployment Guide

RedELK is a Red Team SIEM tool for tracking and analyzing Cobalt Strike, Empire, and other C2 framework logs.

## 🚀 Quick Start - Deploy on Ubuntu Server

### Prerequisites
- Fresh Ubuntu Server (20.04, 22.04, or 24.04 LTS)
- Minimum: 4 CPU cores, 8 GB RAM, 50 GB disk
- Root access or sudo privileges
- Internet connection

### Deployment (5 minutes)

1. **Transfer the deployment script to your Ubuntu server:**
```bash
# From your local machine
scp redelk_ubuntu_deploy.sh root@YOUR_SERVER_IP:/tmp/

# Or download directly on the server
wget https://your-url/redelk_ubuntu_deploy.sh
```

2. **Run the deployment:**
```bash
# SSH into your Ubuntu server
ssh root@YOUR_SERVER_IP

# Optional: Check if server is ready
bash ubuntu_preflight.sh

# Deploy RedELK (takes ~5 minutes)
bash /tmp/redelk_ubuntu_deploy.sh
```

3. **Access RedELK:**
- Open browser: `https://YOUR_SERVER_IP/`
- Login: `redelk` / `redelk`
- **Change password immediately!**

## 📁 Project Structure

```
RedELK/
├── redelk_ubuntu_deploy.sh   # Main deployment script (use this!)
├── ubuntu_preflight.sh        # Pre-deployment checker (optional)
├── elkserver/                 # ELK Stack configuration
│   ├── docker/               # Docker Compose files
│   ├── logstash/            # Logstash pipelines
│   ├── kibana/              # Kibana dashboards
│   └── nginx/               # HTTPS reverse proxy
├── c2servers/                 # C2 server Filebeat configs
├── redirs/                    # Redirector Filebeat configs
├── certs/                     # TLS certificates (auto-generated)
└── scripts/                   # Helper utilities
```

## 🔧 What Gets Installed

The deployment script automatically installs and configures:
- Docker & Docker Compose
- Elasticsearch 8.11.3
- Kibana 8.11.3
- Logstash 8.11.3
- Nginx (HTTPS reverse proxy)
- Filebeat configurations for C2/Redirectors
- TLS certificates
- Firewall rules
- Systemd service

## 🎯 Post-Deployment: Connect Your C2 Infrastructure

### For Cobalt Strike / C2 Servers:
```bash
# The deployment creates: /opt/RedELK/c2servers.tgz
# Copy to your C2 server and extract:
scp /opt/RedELK/c2servers.tgz root@C2_SERVER:/tmp/
ssh root@C2_SERVER
cd /tmp && tar xzf c2servers.tgz

# Install Filebeat and use the provided config
```

### For Redirectors:
```bash
# The deployment creates: /opt/RedELK/redirs.tgz
# Copy to your redirector and extract:
scp /opt/RedELK/redirs.tgz root@REDIRECTOR:/tmp/
ssh root@REDIRECTOR
cd /tmp && tar xzf redirs.tgz

# Install Filebeat and use the provided config
```

## 🔐 Default Credentials

**Change these immediately after deployment!**

| Service | Username | Password |
|---------|----------|----------|
| Kibana UI | redelk | redelk |
| Elasticsearch | elastic | RedElk2024Secure! |
| Kibana System | kibana_system | KibanaRedElk2024! |

## 🛠️ Management Commands

```bash
# Service control
systemctl status redelk      # Check status
systemctl restart redelk     # Restart stack
systemctl stop redelk        # Stop stack

# View logs
docker logs redelk-elasticsearch
docker logs redelk-kibana
docker logs redelk-logstash

# Access containers
docker exec -it redelk-elasticsearch bash
docker exec -it redelk-kibana bash

# Check all containers
docker ps | grep redelk
```

## 🔍 Verify Deployment

```bash
# Check services are running
curl -k -u elastic:RedElk2024Secure! https://localhost:9200

# Check Logstash port
netstat -tlnp | grep 5044

# Check disk usage
df -h /opt/RedELK
```

## 📊 Using RedELK

1. **Import Dashboards**: Kibana → Stack Management → Saved Objects → Import
2. **Configure Index Patterns**: `redelk-*` for C2 logs
3. **Set Time Range**: Last 30 days to see historical data
4. **Create Alerts**: Watcher/Rules for suspicious activity

## 🚨 Troubleshooting

If deployment fails:
1. Check logs: `/opt/RedELK/logs/install.log`
2. Verify Docker: `docker --version`
3. Check ports: `netstat -tlnp | grep -E "443|5044"`
4. Restart: `systemctl restart redelk`

## 📚 Documentation

- Official RedELK: https://github.com/outflanknl/RedELK
- Wiki: https://github.com/outflanknl/RedELK/wiki
- Issues: https://github.com/outflanknl/RedELK/issues

## 🔒 Security Notes

- Always use HTTPS (port 443)
- Change all default passwords
- Restrict firewall to trusted IPs
- Enable 2FA in Kibana
- Regularly update Docker images
- Monitor disk space (logs grow quickly)

## 🎬 Quick Test

After deployment, test with sample data:
```bash
# On the RedELK server
echo '{"@timestamp":"2024-01-01T12:00:00","message":"test"}' | \
  nc localhost 5044
```

---

**Ready to Deploy?** Just run `bash redelk_ubuntu_deploy.sh` on your Ubuntu server! 🚀

*RedELK v3.0 - Red Team SIEM by Outflank*