# RedELK v3.0 - Deployment Instructions

## Quick Start

### 1. Copy to Server
```bash
scp redelk-v3-deployment.tar.gz root@10.10.0.69:/tmp/
```

### 2. Deploy on Server
```bash
ssh root@10.10.0.69

# Clean up any previous installation
systemctl stop redelk 2>/dev/null || true
docker compose -f /opt/RedELK/elkserver/docker/docker-compose.yml down -v 2>/dev/null || true
rm -rf /opt/RedELK

# Extract and deploy
cd /tmp
tar xzf redelk-v3-deployment.tar.gz
cd DEPLOYMENT-BUNDLE
sudo bash redelk_ubuntu_deploy.sh
```

### 3. Access RedELK
- **URL**: https://10.10.0.69/
- **Username**: elastic
- **Password**: RedElk2024Secure

The deployment will show dashboards immediately after completion.

---

## Expected Deployment Time

- **Fast system** (SSD, 16GB RAM): 4-5 minutes
- **Average system** (SSD, 8GB RAM): 7-8 minutes
- **Slow system** (HDD, 4GB RAM): 15-20 minutes

All systems will complete successfully. Slower systems just take longer.

---

## Deploy to C2 Servers

After RedELK is running, deploy Filebeat to your C2 servers:

```bash
# Copy package from RedELK server
scp root@10.10.0.69:/tmp/c2servers.tgz root@POLARIS:/tmp/

# Deploy on C2 server
ssh root@POLARIS
cd /tmp
tar xzf c2servers.tgz
cd c2package
sudo bash deploy-filebeat-c2.sh
```

---

## Deploy to Redirectors

```bash
# Copy package from RedELK server
scp root@10.10.0.69:/tmp/redirs.tgz root@REDIRECTOR:/tmp/

# Deploy on redirector
ssh root@REDIRECTOR
cd /tmp
tar xzf redirs.tgz
cd redirpackage
sudo bash deploy-filebeat-redir.sh
```

---

## Verify Deployment

```bash
# Check all services running
docker ps

# Check Elasticsearch
curl -u elastic:RedElk2024Secure http://localhost:9200

# Check Kibana
curl http://localhost:5601/api/status

# Check Logstash
curl http://localhost:9600/?pretty

# View logs
docker logs redelk-elasticsearch
docker logs redelk-logstash
docker logs redelk-kibana
```

---

## Troubleshooting

### Dashboards Not Showing

If dashboards didn't import automatically, retry:
```bash
sudo bash /tmp/fix-dashboards.sh
```

### Service Won't Start

Check logs for the failing service:
```bash
docker logs redelk-elasticsearch
docker logs redelk-logstash
docker logs redelk-kibana
```

### Deployment Failed

Full deployment log is available:
```bash
cat /var/log/redelk_deploy.log
```

---

## Service Management

```bash
# Stop all services
systemctl stop redelk

# Start all services
systemctl start redelk

# Restart all services
systemctl restart redelk

# Check status
systemctl status redelk
```
