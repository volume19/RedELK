# RedELK v3.0 Troubleshooting Guide

This guide covers common issues and their solutions.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Service Issues](#service-issues)
- [Performance Issues](#performance-issues)
- [Network Issues](#network-issues)
- [Data Issues](#data-issues)
- [Certificate Issues](#certificate-issues)
- [Useful Commands](#useful-commands)

---

## Installation Issues

### Pre-flight Checks Failing

#### Not Running as Root
```bash
Error: Must run as root
```

**Solution:**
```bash
sudo python3 install.py
```

#### Docker Not Installed
```bash
Error: Docker not installed
```

**Solution (Ubuntu/Debian):**
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in, or:
newgrp docker
```

#### Docker Compose Not Installed
```bash
Error: Docker Compose not installed
```

**Solution:**
```bash
# For Docker Compose V2 (recommended)
sudo apt-get update
sudo apt-get install docker-compose-plugin

# For older standalone version
sudo curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

#### Insufficient Memory
```bash
Error: Only 3 GB RAM (need 4 GB minimum)
```

**Solutions:**
1. **Use Limited Install:**
   ```bash
   sudo python3 install.py
   # Select "limited" when prompted
   ```

2. **Increase System RAM** (if using VM)

3. **Use Swap Space** (not recommended for production):
   ```bash
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

#### Ports Already in Use
```bash
Warning: Ports in use: 443, 5044
```

**Solution:**
```bash
# Find process using port
sudo netstat -tulpn | grep :443
sudo lsof -i :443

# Stop the conflicting service
sudo systemctl stop apache2  # or nginx, etc.

# Or change RedELK ports in docker-compose.yml
```

---

## Service Issues

### Elasticsearch Won't Start

#### Symptom: Container keeps restarting
```bash
docker ps | grep elasticsearch
# Shows "Restarting..."
```

**Check Logs:**
```bash
docker logs redelk-elasticsearch
```

**Common Causes & Solutions:**

1. **vm.max_map_count Too Low:**
   ```bash
   Error: max virtual memory areas vm.max_map_count [65530] is too low
   ```
   
   **Fix:**
   ```bash
   sudo sysctl -w vm.max_map_count=262144
   echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
   ```

2. **Insufficient Memory:**
   ```bash
   Error: Java heap space
   ```
   
   **Fix:** Reduce ES memory in `elkserver/.env`:
   ```bash
   ES_MEMORY=2g  # Instead of 4g
   ```

3. **Permission Issues:**
   ```bash
   Error: Unable to access config/elasticsearch.yml
   ```
   
   **Fix:**
   ```bash
   sudo chown -R 1000:1000 elkserver/mounts/elasticsearch-config/
   ```

4. **Corrupted Data:**
   ```bash
   Error: Corrupted index
   ```
   
   **Fix (WARNING: Deletes all data):**
   ```bash
   docker-compose -f elkserver/docker-compose.yml down -v
   docker volume rm redelk_es_data
   # Then reinstall
   ```

### Kibana Won't Start

#### Symptom: Can't access Kibana web interface

**Check Status:**
```bash
./redelk status
docker logs redelk-kibana
```

**Common Causes & Solutions:**

1. **Waiting for Elasticsearch:**
   ```
   Log: Waiting for Elasticsearch...
   ```
   
   **Solution:** Wait for Elasticsearch to be healthy first:
   ```bash
   ./redelk health
   # Wait until elasticsearch shows "healthy"
   ```

2. **Certificate Issues:**
   ```
   Error: unable to get local issuer certificate
   ```
   
   **Fix:**
   ```bash
   # Regenerate certificates
   cd certs
   sudo bash ../initial-setup.sh config.cnf
   ```

3. **Wrong Password:**
   ```
   Error: Authentication failed
   ```
   
   **Fix:** Check password in .env matches:
   ```bash
   grep CREDS_kibana_system elkserver/.env
   # Ensure it matches what Elasticsearch expects
   ```

### Logstash Won't Start

**Check Logs:**
```bash
docker logs redelk-logstash
```

**Common Issues:**

1. **Configuration Error:**
   ```
   Error: Expected one of...
   ```
   
   **Fix:** Validate config:
   ```bash
   docker exec redelk-logstash logstash --config.test_and_exit
   ```

2. **Can't Connect to Elasticsearch:**
   ```
   Error: Connection refused
   ```
   
   **Fix:** Ensure Elasticsearch is healthy:
   ```bash
   curl -k -u elastic:PASSWORD https://localhost:9200
   ```

3. **Certificate Problems:**
   ```
   Error: certificate verify failed
   ```
   
   **Fix:** Check certificate paths in docker-compose.yml

### NGINX/BloodHound Issues

#### Can't Access Web Interface

**Diagnostics:**
```bash
# Check NGINX is running
docker ps | grep nginx

# Check NGINX logs
docker logs redelk-nginx

# Test NGINX config
docker exec redelk-nginx nginx -t
```

**Common Fixes:**
1. **Port Conflict:**
   ```bash
   # Change ports in docker-compose.yml
   ports:
     - "8080:80"  # Use 8080 instead of 80
     - "8443:443" # Use 8443 instead of 443
   ```

2. **Certificate Issues:**
   ```bash
   # Use HTTP instead (testing only)
   http://YOUR_SERVER:80
   ```

---

## Performance Issues

### Slow Kibana Response

**Symptoms:**
- Kibana loading slowly
- Queries timing out
- Dashboard not rendering

**Solutions:**

1. **Increase ES Memory:**
   ```bash
   # Edit elkserver/.env
   ES_MEMORY=6g  # Increase from 4g
   
   # Restart
   ./redelk restart elasticsearch
   ```

2. **Optimize Queries:**
   - Use time range filters (last 24h instead of all time)
   - Limit number of results
   - Use aggregations instead of raw data

3. **Clear Old Data:**
   ```bash
   # Delete indices older than 30 days
   curl -X DELETE "localhost:9200/*-$(date -d '30 days ago' +%Y.%m.%d)"
   ```

### High CPU Usage

**Check Resource Usage:**
```bash
./redelk stats
docker stats
```

**Solutions:**

1. **Limit Container Resources:**
   Edit `docker-compose.yml`:
   ```yaml
   deploy:
     resources:
       limits:
         cpus: '2.0'
         memory: 4G
   ```

2. **Reduce Logstash Workers:**
   Edit `elkserver/mounts/logstash-config/logstash.yml`:
   ```yaml
   pipeline.workers: 2  # Reduce from default
   ```

### Disk Space Issues

**Check Disk Usage:**
```bash
df -h
docker system df
```

**Solutions:**

1. **Clean Docker:**
   ```bash
   make prune
   # OR
   docker system prune -a --volumes
   ```

2. **Enable ILM (Index Lifecycle Management):**
   - Automatically deletes old indices
   - Configured in Elasticsearch

3. **Clean Old Logs:**
   ```bash
   make clean-logs
   ```

---

## Network Issues

### Can't Receive Logs from C2/Redirectors

**Symptom:** No data appearing in Kibana

**Diagnostics:**

1. **Check Logstash is Listening:**
   ```bash
   nc -zv YOUR_REDELK_SERVER 5044
   # Should show: Connection succeeded
   ```

2. **Check Firewall:**
   ```bash
   sudo ufw status
   sudo iptables -L
   ```

3. **Test from C2 Server:**
   ```bash
   # On C2 server
   openssl s_client -connect REDELK_SERVER:5044
   ```

**Solutions:**

1. **Open Firewall Port:**
   ```bash
   sudo ufw allow 5044/tcp
   # OR for iptables
   sudo iptables -A INPUT -p tcp --dport 5044 -j ACCEPT
   ```

2. **Check Certificate:**
   ```bash
   # On C2 server
   ls -la /etc/filebeat/redelkCA.crt
   # Should exist and be readable
   ```

3. **Check Filebeat Config:**
   ```bash
   # On C2 server
   filebeat test config
   filebeat test output
   ```

### SSL/TLS Errors

**Symptoms:**
- "certificate verify failed"
- "x509: certificate signed by unknown authority"

**Solutions:**

1. **Regenerate Certificates:**
   ```bash
   cd certs
   # Edit config.cnf with correct domains/IPs
   sudo bash ../initial-setup.sh config.cnf
   ```

2. **Use IP Address:**
   Ensure certificate includes IP address in SAN (Subject Alternative Name)

3. **Disable SSL Verification** (testing only):
   ```bash
   # In filebeat config
   ssl.verification_mode: none
   ```

---

## Data Issues

### No Data in Kibana

**Diagnostics:**

1. **Check Filebeat Status (on C2):**
   ```bash
   systemctl status filebeat
   journalctl -u filebeat -f
   ```

2. **Check Logstash:**
   ```bash
   docker logs redelk-logstash | tail -50
   ```

3. **Check Elasticsearch Indices:**
   ```bash
   curl -k -u elastic:PASSWORD https://localhost:9200/_cat/indices
   ```

**Solutions:**

1. **Restart Filebeat (on C2):**
   ```bash
   sudo systemctl restart filebeat
   ```

2. **Check Index Patterns in Kibana:**
   - Go to Stack Management → Index Patterns
   - Refresh field list

3. **Manually Test Ingestion:**
   ```bash
   # Create test log entry
   echo '{"message": "test"}' | nc YOUR_REDELK_SERVER 5044
   ```

### Data Not Showing in Dashboard

**Solutions:**

1. **Check Time Range:**
   - Click time picker in top right
   - Set to "Last 24 hours" or appropriate range

2. **Refresh Index Pattern:**
   - Stack Management → Index Patterns
   - Select redelk-*
   - Click refresh icon

3. **Check Filters:**
   - Remove any active filters
   - Clear search bar

---

## Certificate Issues

### Let's Encrypt Failures

**Symptom:**
```
Error: Failed to verify domain ownership
```

**Solutions:**

1. **Check DNS:**
   ```bash
   nslookup YOUR_DOMAIN
   # Should resolve to your RedELK server IP
   ```

2. **Check Port 80:**
   ```bash
   # Must be accessible from internet
   curl http://YOUR_DOMAIN/.well-known/acme-challenge/test
   ```

3. **Use Staging:**
   ```bash
   # In .env
   LE_STAGING=1
   # Test first, then use production
   ```

4. **Check Rate Limits:**
   - Let's Encrypt has rate limits
   - Wait an hour and try again

### Self-Signed Certificate Warnings

**Expected Behavior:** Browser shows SSL warning

**Solutions:**

1. **Add Exception in Browser** (testing only)

2. **Import CA Certificate:**
   ```bash
   # Import certs/redelkCA.crt to your browser's trusted CAs
   ```

3. **Use Let's Encrypt** for production

---

## Useful Commands

### Quick Diagnostics
```bash
# Service status
./redelk status
./redelk health

# View logs
./redelk logs --tail=100
./redelk logs --follow

# Check specific service
docker logs redelk-elasticsearch

# Resource usage
./redelk stats
```

### Service Management
```bash
# Restart everything
./redelk restart

# Restart specific service
./redelk restart --service elasticsearch

# Stop/Start
./redelk stop
./redelk start
```

### Data Management
```bash
# Backup
make backup

# View passwords
./redelk passwords

# Clean up
make clean
make clean-logs
```

### Docker Commands
```bash
# Enter container
./redelk shell elasticsearch

# View container processes
./redelk top

# Rebuild images
make rebuild
```

---

## Getting More Help

### Enable Verbose Logging

1. **Installation:**
   ```bash
   python3 install.py --verbose
   ```

2. **Docker Compose:**
   ```bash
   docker-compose --verbose up
   ```

3. **Elasticsearch:**
   Edit `docker-compose.yml`:
   ```yaml
   environment:
     - "ES_JAVA_OPTS=-Xms4g -Xmx4g"
     - "logger.level=DEBUG"
   ```

### Collect Debug Information
```bash
# Create debug bundle
./redelk info > redelk-debug.txt
./redelk status >> redelk-debug.txt
docker-compose -f elkserver/docker-compose.yml logs > redelk-logs.txt
```

### Community Support
- GitHub Issues: https://github.com/outflanknl/RedELK/issues
- Documentation: https://github.com/outflanknl/RedELK/wiki

### Professional Support
Contact the RedELK team for commercial support options.

---

## Emergency Recovery

### Complete Reset (WARNING: Deletes ALL data)
```bash
# Stop all services
./redelk down

# Remove all volumes
docker volume rm redelk_es_data redelk_kibana_data redelk_bloodhound_data redelk_postgres_data

# Remove all containers
docker rm -f $(docker ps -a | grep redelk- | awk '{print $1}')

# Clean up
make clean

# Reinstall
sudo python3 install.py
```

### Backup Before Major Changes
```bash
# Always backup before:
# - Upgrading
# - Changing configuration
# - Debugging complex issues

make backup
```

---

**Last Updated:** October 2024  
**Version:** 3.0.0


