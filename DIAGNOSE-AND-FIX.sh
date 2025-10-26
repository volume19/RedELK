#!/bin/bash
set -e
cd /tmp

P="/opt/RedELK"
PW="RedElk2024Secure"

[ "$EUID" -ne 0 ] && exit 1

echo "RedELK v3 Diagnostic and Fix"
echo "========================================"
echo ""

# AGGRESSIVE CLEANUP
echo "Cleaning everything..."
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker network prune -f >/dev/null 2>&1
docker volume prune -f >/dev/null 2>&1
systemctl stop nginx 2>/dev/null || true
rm -rf "$P"
echo "Clean"
echo ""

# SETUP
echo "Installing dependencies..."
apt-get update -qq && apt-get install -y -qq curl jq openssl >/dev/null 2>&1
sysctl -w vm.max_map_count=262144 >/dev/null 2>&1

mkdir -p "$P"/{d,n,l,c,k,data}
chown -R 1000:1000 "$P/data"

cd "$P/c" && openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout k.pem -out c.pem -subj "/CN=r" 2>/dev/null

echo "Done"
echo ""

# CONFIG
echo "Configuring..."
cd "$P/d"

# FIX 6: Bind-mount ES data instead of named volume
# FIX 1: Kibana service account token (volume mount added)
# FIX 2: Kibana healthcheck added
# FIX 4: Nginx depends_on service_started (not service_healthy)
cat > c.yml <<'EOF'
services:
  es:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.15.3
    container_name: es
    restart: always
    environment:
      discovery.type: single-node
      ELASTIC_PASSWORD: RedElk2024Secure
      xpack.security.enabled: "true"
      xpack.security.http.ssl.enabled: "false"
      xpack.security.transport.ssl.enabled: "false"
      ES_JAVA_OPTS: "-Xms2g -Xmx2g"
    volumes:
      - /opt/RedELK/data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
    networks:
      - n

  ls:
    image: docker.elastic.co/logstash/logstash:8.15.3
    container_name: ls
    restart: always
    environment:
      ELASTIC_PASSWORD: RedElk2024Secure
    volumes:
      - /opt/RedELK/l:/usr/share/logstash/pipeline:ro
    ports:
      - "5044:5044"
    networks:
      - n

  kb:
    image: docker.elastic.co/kibana/kibana:8.15.3
    container_name: kb
    restart: always
    environment:
      ELASTICSEARCH_HOSTS: "http://es:9200"
      SERVER_HOST: "0.0.0.0"
    volumes:
      - /opt/RedELK/k/kibana.yml:/usr/share/kibana/config/kibana.yml:ro
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:5601/api/status | grep -q '\"level\":\"available\"'"]
      interval: 15s
      timeout: 10s
      retries: 80
      start_period: 180s
    ports:
      - "5601:5601"
    networks:
      - n

  nx:
    image: nginx:alpine
    container_name: nx
    restart: always
    depends_on:
      kb:
        condition: service_started
    volumes:
      - /opt/RedELK/n/n.conf:/etc/nginx/nginx.conf:ro
      - /opt/RedELK/c:/c:ro
    ports:
      - "80:80"
      - "443:443"
    networks:
      - n

networks:
  n:
EOF

# FIX 5: Clean, known-good Nginx config
cat > "$P/n/n.conf" <<'EOF'
events { worker_connections 1024; }
http {
  upstream kibana_upstream { server kb:5601; }
  server { listen 80; return 301 https://$host$request_uri; }
  server {
    listen 443 ssl http2;
    ssl_certificate     /c/c.pem;
    ssl_certificate_key /c/k.pem;

    location / {
      proxy_pass http://kibana_upstream;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_buffering off;
    }
  }
}
EOF

# FIX 3: Fix Logstash pipeline syntax with proper whitespace
cat > "$P/l/m.conf" <<'EOF'
input {
  beats {
    port => 5044
    ssl  => false
  }
}

output {
  elasticsearch {
    hosts    => ["http://es:9200"]
    user     => "elastic"
    password => "RedElk2024Secure"
    index    => "r-%{+YYYY.MM.dd}"
  }
}
EOF

echo "Done"
echo ""

# DEPLOY
echo "Deploying RedELK Stack"
echo "========================================"

echo "Starting Elasticsearch..."
docker compose -f c.yml up -d es

# FIX 7: Replace fixed sleep with readiness check
echo "Waiting for Elasticsearch to be ready..."
until curl -sf -u elastic:$PW http://127.0.0.1:9200 >/dev/null 2>&1; do
  echo -n "."
  sleep 3
done
echo " OK"

# FIX 1 & 8: Create Kibana service account token (unnamed, no conflicts)
echo "Creating Kibana service account token..."
TOKEN=$(curl -sS -u elastic:$PW -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:9200/_security/service/elastic/kibana/credential/token/create \
  2>/dev/null | jq -r '.token.value')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Failed to create Kibana token"
  exit 1
fi

# FIX 1 & 9: Write kibana.yml with service account token and proper permissions
cat > "$P/k/kibana.yml" <<EOF
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://es:9200"]
elasticsearch.serviceAccountToken: "${TOKEN}"
telemetry.enabled: false
logging.root.level: "warn"
EOF

chown 1000:0 "$P/k/kibana.yml"
chmod 640 "$P/k/kibana.yml"
echo "Kibana config created with service account token"

echo ""
echo "Starting Logstash..."
docker compose -f c.yml up -d ls
sleep 10

echo "Checking Logstash..."
if docker logs ls 2>&1 | grep -q "Pipeline started"; then
  echo "  Logstash: OK"
else
  echo "  Logstash logs:"
  docker logs ls 2>&1 | tail -10
fi

echo ""
echo "Starting Kibana..."
docker compose -f c.yml up -d kb

# FIX 7: Replace fixed sleep with readiness check
echo "Waiting for Kibana to be ready..."
until curl -sf http://127.0.0.1:5601/api/status 2>/dev/null | grep -q '"level":"available"'; do
  echo -n "."
  sleep 5
done
echo " OK"

echo ""
echo "Starting Nginx..."
docker compose -f c.yml up -d nx
sleep 5

# FIX 5: Validate Nginx config
echo "Validating Nginx configuration..."
docker exec nx nginx -t 2>&1 || {
  echo "ERROR: Nginx config validation failed"
  docker logs nx --tail=50
  exit 1
}

# FINAL STATUS
echo ""
echo "========================================"
echo "FINAL STATUS"
echo "========================================"
echo ""

docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
RUNNING=$(docker ps --filter "name=^(es|ls|kb|nx)$" --format "{{.Names}}" | wc -l)
echo "Running: $RUNNING/4 services"

if [ "$RUNNING" -ne 4 ]; then
  echo ""
  echo "MISSING SERVICES - Checking why:"
  for s in es ls kb nx; do
    if ! docker ps --filter "name=^${s}$" --format "{{.Names}}" | grep -q "^${s}$"; then
      echo ""
      echo "=== $s crashed ==="
      docker logs "$s" 2>&1 | tail -30
    fi
  done
  exit 1
fi

# CONNECTIVITY TEST
echo ""
echo "Testing connectivity..."

echo -n "  Elasticsearch: "
curl -s -u elastic:$PW http://127.0.0.1:9200 >/dev/null 2>&1 && echo "OK" || echo "FAIL"

echo -n "  Kibana: "
curl -s http://127.0.0.1:5601/api/status >/dev/null 2>&1 && echo "OK" || echo "FAIL"

echo -n "  Nginx: "
curl -s -k https://127.0.0.1 >/dev/null 2>&1 && echo "OK" || echo "FAIL"

IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)

echo ""
echo "========================================"
echo "ACCESS"
echo "========================================"
echo ""
echo "URL: https://${IP}/"
echo "User: elastic"
echo "Pass: RedElk2024Secure"
echo ""
echo "All services running successfully!"
echo "========================================"
echo ""
