# RedELK v3.0 Quick Start Guide

This guide will get you up and running with RedELK in minutes.

## Prerequisites

- **Operating System**: Ubuntu 22.04 LTS or Debian 12 (recommended)
- **Memory**: Minimum 4GB RAM (8GB+ recommended for full install)
- **Disk Space**: 20GB+ free disk space
- **Docker**: Docker 20.10+ and Docker Compose v2
- **Root Access**: Required for installation
- **Python**: Python 3.8+ (usually pre-installed)

## Quick Installation (Recommended for Testing)

The fastest way to get RedELK running:

```bash
# Clone the repository
git clone https://github.com/outflanknl/RedELK.git
cd RedELK

# Run quick start installation
sudo python3 install.py --quickstart
```

This will:
- ✅ Auto-detect system configuration
- ✅ Use sensible defaults
- ✅ Generate all certificates automatically
- ✅ Create random secure passwords
- ✅ Start all services

**Installation time**: 5-10 minutes depending on your internet speed

## Interactive Installation (Recommended for Production)

For production deployments, use the interactive installer to customize your setup:

```bash
sudo python3 install.py
```

The installer will guide you through:
1. **Installation Type**: Full or Limited
2. **Server Address**: Domain name or IP
3. **TLS Certificates**: Let's Encrypt or self-signed
4. **Project Name**: Your operation name
5. **Notifications**: Email, Slack, MS Teams
6. **Infrastructure Size**: Number of team servers

## Using Make Commands

After installation, manage RedELK with convenient make commands:

```bash
# View all available commands
make help

# Common operations
make status          # Check service status
make logs           # View logs (follow mode)
make restart        # Restart all services
make stop           # Stop services
make start          # Start services

# Useful info
make passwords      # Display credentials
make urls          # Show access URLs
make info          # System information
```

## Post-Installation

### 1. Access RedELK Kibana

Open your browser to:
```
https://YOUR_SERVER_IP/
```

**Default Credentials:**
- Username: `redelk`
- Password: See `elkserver/redelk_passwords.cfg`

### 2. View Your Passwords

```bash
make passwords
# OR
cat elkserver/redelk_passwords.cfg
```

### 3. Configure C2 Server Agents

On each Command & Control server:

```bash
# Copy the c2servers.tgz to your C2 server
scp c2servers.tgz root@c2server:/tmp/

# On the C2 server:
cd /tmp
tar xzf c2servers.tgz
cd c2servers
sudo ./install-c2server.sh <hostname> <attackscenario> <redelk-server-ip>:5044
```

Example:
```bash
sudo ./install-c2server.sh cs-team1 operation-phoenix 192.168.1.100:5044
```

### 4. Configure Redirector Agents

On each redirector:

```bash
# Copy the redirs.tgz to your redirector
scp redirs.tgz root@redirector:/tmp/

# On the redirector:
cd /tmp
tar xzf redirs.tgz
cd redirs
sudo ./install-redir.sh <hostname> <attackscenario> <redelk-server-ip>:5044
```

Example:
```bash
sudo ./install-redir.sh redir-web1 operation-phoenix 192.168.1.100:5044
```

## Accessing Services

### Kibana (Main Dashboard)
```
URL: https://YOUR_SERVER/
User: redelk
Pass: [see passwords file]
```

### Jupyter Notebooks (Full Install)
```
URL: https://YOUR_SERVER/jupyter
User: redelk
Pass: [see passwords file]
```

### BloodHound (Full Install)
```
URL: https://YOUR_SERVER:8443
User: admin
Pass: [see passwords file]
```

### Neo4j Browser (Full Install)
```
URL: http://YOUR_SERVER:7474
User: neo4j
Pass: [see passwords file]
```

## Verifying Installation

### Check Service Status

```bash
make status
```

All services should show as "Up" or "healthy".

### Check Logs

```bash
# Follow all logs
make logs

# Check for errors
make logs-errors

# View specific service
cd elkserver && docker-compose logs elasticsearch
```

### Test Log Ingestion

```bash
# Check if Logstash is listening
nc -zv YOUR_SERVER_IP 5044

# Should return: Connection to YOUR_SERVER_IP 5044 port [tcp/*] succeeded!
```

## Troubleshooting

### Services Won't Start

```bash
# Check Docker is running
sudo systemctl status docker

# Check available memory
free -h

# Check disk space
df -h

# View detailed logs
cd elkserver && docker-compose logs elasticsearch
```

### Can't Access Kibana

1. **Check Kibana is running:**
   ```bash
   docker ps | grep kibana
   ```

2. **Check Kibana logs:**
   ```bash
   docker logs redelk-kibana
   ```

3. **Verify certificates:**
   ```bash
   ls -la elkserver/mounts/certs/
   ```

### Elasticsearch Won't Start

Common issues:
- **Insufficient memory**: Increase RAM or use limited install
- **vm.max_map_count too low**: Should be set to 262144
- **Port 9200 in use**: Check with `netstat -tulpn | grep 9200`

```bash
# Fix vm.max_map_count
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### Forgot Passwords

```bash
make passwords
```

## Common Operations

### Restart After Configuration Changes

```bash
make restart
```

### Update RedELK

```bash
make update
make rebuild
make restart
```

### View Real-Time Logs

```bash
make logs
```

### Backup Your Data

```bash
make backup
```

### Clean Up Old Logs

```bash
make clean-logs
```

## What's Next?

1. **Configure Alarms**: Edit `elkserver/mounts/redelk-config/etc/redelk/config.json`
   - Add VirusTotal API keys
   - Configure email notifications
   - Set up Slack/Teams webhooks

2. **Add Team Servers**: Deploy agents to your C2 infrastructure

3. **Add Redirectors**: Configure your redirectors to send logs

4. **Explore Dashboards**: 
   - Overview dashboard
   - Traffic analysis
   - IOC tracking
   - MITRE ATT&CK Navigator
   - Screenshots and downloads

5. **Set Up Cron Jobs**: Edit `elkserver/mounts/redelk-config/etc/cron.d/redelk`

## Getting Help

- **Documentation**: https://github.com/outflanknl/RedELK/wiki
- **Issues**: https://github.com/outflanknl/RedELK/issues
- **Logs**: `make logs` or check `/var/log/redelk/`

## Security Notes

- Change default passwords in production
- Use Let's Encrypt for production deployments
- Restrict access to ports 5044, 9200, 5601
- Use VPN or SSH tunnels for remote access
- Regularly update RedELK and Docker images

## Performance Tuning

For large operations:

1. **Increase Memory**: Allocate more RAM to Elasticsearch
2. **Add Storage**: Use dedicated SSD for Docker volumes
3. **Tune JVM**: Edit `elkserver/mounts/elasticsearch-config/jvm.options.d/jvm.options`
4. **Optimize Queries**: Use time range filters in Kibana

---

**Happy Red Teaming! 🔴⚡**

For advanced configuration and troubleshooting, see:
- [Architecture Guide](ARCHITECTURE.md)
- [Configuration Reference](CONFIGURATION.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)


