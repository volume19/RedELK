# RedELK v3.0

One-script deployment for RedELK SIEM on Ubuntu.

## Requirements

- Ubuntu 20.04/22.04/24.04 LTS (fresh install)
- Root access
- 4+ CPU, 8+ GB RAM, 50+ GB disk

## Clean Install

```bash
# Download and run
curl -o /tmp/install.sh https://raw.githubusercontent.com/volume19/RedELK/master/redelk_ubuntu_deploy.sh
sudo bash /tmp/install.sh
```

## Access

After 5 minutes:
- URL: `https://YOUR_SERVER_IP/`
- User: `elastic`
- Pass: `RedElk2024Secure`

## Cleanup (if needed)

```bash
# Stop and remove everything
cd /opt/RedELK/elkserver/docker 2>/dev/null && docker compose down -v
docker rm -f $(docker ps -a | grep redelk | awk '{print $1}') 2>/dev/null
docker network rm redelk_redelk 2>/dev/null
sudo rm -rf /opt/RedELK
sudo rm -f /etc/systemd/system/redelk.service
sudo rm -f /etc/sysctl.d/99-elasticsearch.conf
```

## Files

- `redelk_ubuntu_deploy.sh` - Main deployment script
- `.env.example` - Environment template
- `linux/99-elastic.conf` - Kernel settings