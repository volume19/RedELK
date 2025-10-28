# RedELK v3.0.7 - Deployment Guide

**Bundle**: redelk-v3-deployment.tar.gz (48KB)
**Status**: Production Ready

---

## Quick Start

### 1. Transfer Bundle
```bash
scp redelk-v3-deployment.tar.gz root@YOUR_SERVER:/tmp/
```

### 2. Deploy
```bash
ssh root@YOUR_SERVER
cd /tmp
tar xzf redelk-v3-deployment.tar.gz
cd DEPLOYMENT-BUNDLE
sudo bash install-redelk.sh
```

### 3. Access
- **Kibana**: http://YOUR_SERVER:5601
- **Elasticsearch**: http://YOUR_SERVER:9200
- **Credentials**: `elastic` / `RedElk2024Secure`

---

## Validation

### Pre-Deployment
```bash
# Validate bundle structure (on dev machine)
bash bundle_self_test.sh redelk-v3-deployment.tar.gz
```

### Expected Output
```
PRE-FLIGHT CHECKS: 7/7 PASS
  - 11 Logstash configs found
  - 3 Elasticsearch templates found
  - 1 Kibana dashboard found (>2KB)
  
FILE COPY: All files verified
  - 11 configs → conf.d/
  - 11 configs → pipelines/
  
LOGSTASH VALIDATION: Configuration OK

POST-FLIGHT CHECKS: 6/6 PASS
  - Elasticsearch: yellow/green
  - Logstash API: responding
  - Port 5044: listening
  - Kibana: available
  - Dashboards: imported
```

---

## Clean Redeploy

To completely wipe and redeploy:
```bash
# On server
cd /tmp
rm -rf DEPLOYMENT-BUNDLE redelk-v3-deployment.tar.gz

# Transfer new bundle
scp redelk-v3-deployment.tar.gz root@YOUR_SERVER:/tmp/

# Deploy
ssh root@YOUR_SERVER
cd /tmp
tar xzf redelk-v3-deployment.tar.gz
cd DEPLOYMENT-BUNDLE
sudo bash install-redelk.sh
```

The installer automatically cleans previous installations.

---

## Troubleshooting

### View Logs
```bash
docker logs redelk-elasticsearch
docker logs redelk-logstash
docker logs redelk-kibana
tail -f /var/log/redelk_deploy.log
```

### Check Services
```bash
systemctl status redelk
docker ps
ss -ltn | grep -E '9200|5044|5601'
```

### Health Check
```bash
/opt/RedELK/scripts/redelk-health-check.sh
```

---

## Architecture

- **Elasticsearch** (9200): Data store, single-node cluster
- **Logstash** (5044, 9600): Pipeline processing with 11 modular configs
- **Kibana** (5601): Visualization and dashboards
- **Nginx** (80, 443): Reverse proxy for secure access

**Data Retention**: 30-day ILM policy (hot → warm → delete)

---

## File Locations

- **Installation**: `/opt/RedELK/`
- **Configs**: `/opt/RedELK/elkserver/logstash/pipelines/`
- **Data**: `/opt/RedELK/elasticsearch-data/`
- **Logs**: `/var/log/redelk_deploy.log`
- **Scripts**: `/opt/RedELK/scripts/`

---

## Documentation

- **CHANGELOG.md**: Version history and fixes
- **DONE.md**: Completion checklist
- **AUDIT/docs_evidence.md**: Elastic Stack documentation references

---

**For issues**: Check logs, verify Docker is running, ensure port 5044 is not blocked by firewall.
