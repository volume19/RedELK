# RedELK v3.0

One-script deployment of RedELK SIEM for Red Teams. Track Cobalt Strike, Empire, and other C2 logs.

## Deploy in 5 Minutes

```bash
# 1. Clone
git clone https://github.com/volume19/RedELK.git

# 2. Copy to Ubuntu server (20.04/22.04/24.04)
scp RedELK/redelk_ubuntu_deploy.sh root@YOUR_SERVER:/tmp/

# 3. Deploy
ssh root@YOUR_SERVER
bash /tmp/redelk_ubuntu_deploy.sh
```

**Done!** Access at `https://YOUR_SERVER/` • Login: `redelk` / `redelk`

## What's Included

- `redelk_ubuntu_deploy.sh` - Complete automated deployment
- `ubuntu_preflight.sh` - Optional system checker
- `README.md` - This file

## Requirements

- Ubuntu Server 20.04/22.04/24.04 LTS
- 4+ CPU cores, 8+ GB RAM, 50+ GB disk
- Root access & internet connection

## The Script Installs

✓ Docker & Docker Compose
✓ Elasticsearch, Kibana, Logstash (8.11.3)
✓ Nginx HTTPS reverse proxy
✓ TLS certificates
✓ Firewall rules
✓ Systemd service
✓ C2 & Redirector packages

## After Deployment

1. **Change passwords immediately**
2. Deploy Filebeat on C2 servers: `/opt/RedELK/c2servers.tgz`
3. Deploy Filebeat on redirectors: `/opt/RedELK/redirs.tgz`

## Commands

```bash
systemctl status redelk    # Check status
systemctl restart redelk   # Restart
docker logs redelk-kibana  # View logs
```

## Documentation

- [Official RedELK](https://github.com/outflanknl/RedELK)
- [Wiki](https://github.com/outflanknl/RedELK/wiki)

---

*RedELK by Outflank • Simplified deployment by volume19*