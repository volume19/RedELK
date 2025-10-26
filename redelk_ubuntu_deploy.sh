#!/usr/bin/env bash
# RedELK v3.0 - Production Deployment Script
# Fully idempotent, non-interactive deployment for Ubuntu 20.04/22.04/24.04

set -Eeuo pipefail
trap 'echo "Error at line $LINENO: $BASH_COMMAND" >&2' ERR
cd / || true
umask 077

# Normalize potential CRLF/BOM if this file was copied via Windows
sed -i 's/\r$//' "$0" 2>/dev/null || true
sed -i '1s/^\xEF\xBB\xBF//' "$0" 2>/dev/null || true

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/redelk_deploy.log"
readonly REDELK_PATH="/opt/RedELK"
readonly ELASTIC_PASSWORD="RedElk2024Secure"
readonly ES_JAVA_OPTS="-Xms2g -Xmx2g"
readonly KIBANA_CONFIG_DIR="${REDELK_PATH}/elkserver/kibana"

# Export for Docker Compose
export REDELK_PATH ELASTIC_PASSWORD ES_JAVA_OPTS

# Detect Docker Compose command
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    readonly COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    readonly COMPOSE_CMD="docker-compose"
else
    echo "Docker Compose not found"
    exit 1
fi

# Logging setup
exec > >(tee -a "$LOG_FILE")
exec 2>&1

print_banner() {
    echo ""
    echo "    ____            _  _____  _      _  __"
    echo "   |  _ \  ___   __| || ____|| |    | |/ /"
    echo "   | |_) |/ _ \ / _  ||  _|  | |    | ' / "
    echo "   |  _ <|  __/| (_| || |___ | |___ | . \ "
    echo "   |_| \_\___| \____||_____||_____||_|\_\ "
    echo ""
    echo "   Ubuntu Server Deployment v3.0"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] This script must be run as root"
        exit 1
    fi
}

print_facts() {
    echo "[INFO] Host: $(hostname)"
    echo "[INFO] OS: $(lsb_release -ds 2>/dev/null || echo "Unknown")"
    echo "[INFO] Docker: $(docker --version 2>/dev/null || echo "Not installed")"
    echo "[INFO] Compose: $COMPOSE_CMD"
    echo "[INFO] REDELK_PATH: $REDELK_PATH"
    echo "[INFO] Timestamp: $(date -Iseconds)"
}

check_ubuntu() {
    if ! command -v lsb_release > /dev/null 2>&1; then
        echo "[ERROR] This script requires Ubuntu"
        exit 1
    fi

    local version=$(lsb_release -rs)
    case "$version" in
        20.04|22.04|24.04)
            echo "[INFO] Ubuntu $version detected"
            ;;
        *)
            echo "[ERROR] Unsupported Ubuntu version: $version"
            exit 1
            ;;
    esac
}

install_dependencies() {
    echo "[INFO] Installing dependencies..."
    apt-get update -qq
    apt-get install -y -qq \
        curl \
        openssl \
        ca-certificates \
        gnupg \
        lsb-release \
        net-tools \
        iproute2 \
        jq
}

install_docker() {
    if command -v docker > /dev/null 2>&1; then
        echo "[INFO] Docker already installed"
        return
    fi

    echo "[INFO] Installing Docker..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl start docker
    systemctl enable docker
}

setup_kernel() {
    echo "[INFO] Configuring kernel parameters..."
    sysctl -w vm.max_map_count=262144 >/dev/null 2>&1

    cat > /etc/sysctl.d/99-elasticsearch.conf <<EOF
vm.max_map_count=262144
EOF

    sysctl --system >/dev/null 2>&1
}

cleanup_existing_deployment() {
    echo ""
    echo "========================================"
    echo "CLEANUP - Removing existing deployment"
    echo "========================================"
    echo ""

    if systemctl is-active --quiet redelk 2>/dev/null; then
        echo "[INFO] Stopping RedELK systemd service..."
        systemctl stop redelk 2>/dev/null || true
        systemctl disable redelk 2>/dev/null || true
    fi

    echo "[INFO] Removing RedELK containers..."
    docker rm -f redelk-elasticsearch redelk-logstash redelk-kibana redelk-nginx 2>/dev/null || true
    docker rm -f es ls kb nx 2>/dev/null || true

    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo "[INFO] Stopping system nginx..."
        systemctl stop nginx 2>/dev/null || true
    fi

    if [[ -f "${REDELK_PATH}/elkserver/docker/docker-compose.yml" ]]; then
        echo "[INFO] Stopping docker-compose stack..."
        cd "${REDELK_PATH}/elkserver/docker" && docker compose down -v 2>/dev/null || true
    fi

    echo "[INFO] Pruning Docker networks and volumes..."
    docker network prune -f >/dev/null 2>&1 || true
    docker volume prune -f >/dev/null 2>&1 || true

    if [[ -d "${REDELK_PATH}" ]]; then
        echo "[INFO] Removing ${REDELK_PATH}..."
        rm -rf "${REDELK_PATH}"
    fi

    if [[ -f /etc/systemd/system/redelk.service ]]; then
        echo "[INFO] Removing systemd service..."
        rm -f /etc/systemd/system/redelk.service
        systemctl daemon-reload 2>/dev/null || true
    fi

    echo "[INFO] Cleanup complete"
    echo "========================================"
    echo ""
}

create_directories() {
    echo "[INFO] Creating directory structure..."
    mkdir -p "${REDELK_PATH}"/{elkserver/{docker,nginx,logstash/pipelines,kibana},certs,logs}
    mkdir -p "${REDELK_PATH}/elasticsearch-data"

    # Fix permissions for Docker containers (uid 1000)
    chown -R 1000:1000 "${REDELK_PATH}/elasticsearch-data"
    chmod 755 "${REDELK_PATH}/elkserver/logstash"
    chmod 755 "${REDELK_PATH}/elkserver/logstash/pipelines"
}

copy_deployment_files() {
    echo "[INFO] Copying RedELK component files from script directory..."

    mkdir -p "${REDELK_PATH}/elkserver/elasticsearch/index-templates"
    mkdir -p "${REDELK_PATH}/elkserver/logstash/conf.d"
    mkdir -p "${REDELK_PATH}/elkserver/logstash/threat-feeds"
    mkdir -p "${REDELK_PATH}/elkserver/kibana/dashboards"
    mkdir -p "${REDELK_PATH}/scripts"
    mkdir -p "${REDELK_PATH}/c2servers"
    mkdir -p "${REDELK_PATH}/redirs"

    if ls "${SCRIPT_DIR}"/*-template.json >/dev/null 2>&1; then
        echo "[INFO] Copying Elasticsearch index templates..."
        cp "${SCRIPT_DIR}"/*-template.json "${REDELK_PATH}/elkserver/elasticsearch/index-templates/" 2>/dev/null || true
    fi

    if ls "${SCRIPT_DIR}"/*.conf >/dev/null 2>&1; then
        echo "[INFO] Copying Logstash pipeline configurations..."
        cp "${SCRIPT_DIR}"/*.conf "${REDELK_PATH}/elkserver/logstash/conf.d/" 2>/dev/null || true
        chmod 644 "${REDELK_PATH}/elkserver/logstash/conf.d/"*.conf 2>/dev/null || true
    fi

    for feed_file in tor-exit-nodes.txt cdn-ip-lists.txt compromised-ips.txt feodo-tracker.txt talos-reputation.txt; do
        if [[ -f "${SCRIPT_DIR}/${feed_file}" ]]; then
            echo "[INFO] Copying threat feed: ${feed_file}"
            cp "${SCRIPT_DIR}/${feed_file}" "${REDELK_PATH}/elkserver/logstash/threat-feeds/" 2>/dev/null || true
        fi
    done

    if ls "${SCRIPT_DIR}"/*.ndjson >/dev/null 2>&1; then
        echo "[INFO] Copying Kibana dashboards..."
        cp "${SCRIPT_DIR}"/*.ndjson "${REDELK_PATH}/elkserver/kibana/dashboards/" 2>/dev/null || true
    fi

    for script in redelk-health-check.sh redelk-beacon-manager.sh update-threat-feeds.sh verify-deployment.sh; do
        if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
            echo "[INFO] Copying helper script: ${script}"
            cp "${SCRIPT_DIR}/${script}" "${REDELK_PATH}/scripts/"
            chmod +x "${REDELK_PATH}/scripts/${script}"
        fi
    done

    if ls "${SCRIPT_DIR}"/filebeat-*.yml >/dev/null 2>&1; then
        echo "[INFO] Copying Filebeat configurations..."
        for config in filebeat-cobaltstrike.yml filebeat-poshc2.yml filebeat-sliver.yml; do
            [[ -f "${SCRIPT_DIR}/${config}" ]] && cp "${SCRIPT_DIR}/${config}" "${REDELK_PATH}/c2servers/"
        done
        for config in filebeat-apache.yml filebeat-nginx.yml filebeat-haproxy.yml; do
            [[ -f "${SCRIPT_DIR}/${config}" ]] && cp "${SCRIPT_DIR}/${config}" "${REDELK_PATH}/redirs/"
        done
    fi

    echo "[INFO] Component files copied successfully"
}

generate_certificates() {
    echo "[INFO] Generating TLS certificates..."
    local cert_dir="${REDELK_PATH}/certs"

    if [[ -f "${cert_dir}/elkserver.crt" && -f "${cert_dir}/redelkCA.crt" && -f "${cert_dir}/sshkey" ]]; then
        echo "[INFO] Certificates already exist, skipping"
        return
    fi

    local server_ip
    server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -z "$server_ip" ]] && server_ip="$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)"

    cat > "${cert_dir}/config.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = redelk.local

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = redelk.local
DNS.3 = elasticsearch
DNS.4 = kibana
IP.1 = 127.0.0.1
IP.2 = ${server_ip}
EOF

    openssl genrsa -out "${cert_dir}/redelkCA.key" 4096 2>/dev/null
    openssl req -new -x509 -days 3650 -key "${cert_dir}/redelkCA.key" -out "${cert_dir}/redelkCA.crt" \
        -subj "/CN=RedELK CA" 2>/dev/null

    openssl genrsa -out "${cert_dir}/elkserver.key" 4096 2>/dev/null
    openssl req -new -key "${cert_dir}/elkserver.key" -out "${cert_dir}/elkserver.csr" -config "${cert_dir}/config.cnf" 2>/dev/null
    openssl x509 -req -in "${cert_dir}/elkserver.csr" -CA "${cert_dir}/redelkCA.crt" -CAkey "${cert_dir}/redelkCA.key" \
        -CAcreateserial -out "${cert_dir}/elkserver.crt" -days 3650 -extensions v3_req \
        -extfile "${cert_dir}/config.cnf" 2>/dev/null

    rm -f "${cert_dir}/sshkey" "${cert_dir}/sshkey.pub"
    ssh-keygen -t ed25519 -f "${cert_dir}/sshkey" -N "" -q

    chmod 600 "${cert_dir}/elkserver.key" "${cert_dir}/redelkCA.key" "${cert_dir}/sshkey" 2>/dev/null || true
}

fix_permissions() {
    echo "[INFO] Fixing permissions on bind-mounted paths..."

    # Make base directory and package directories accessible
    chmod 755 "${REDELK_PATH}"

    for d in \
        "${REDELK_PATH}/certs" \
        "${REDELK_PATH}/elkserver" \
        "${REDELK_PATH}/elkserver/docker" \
        "${REDELK_PATH}/elkserver/nginx" \
        "${REDELK_PATH}/elkserver/kibana" \
        "${REDELK_PATH}/elkserver/logstash" \
        "${REDELK_PATH}/elkserver/logstash/pipelines" \
        "${REDELK_PATH}/elkserver/logstash/conf.d" \
        "${REDELK_PATH}/elkserver/logstash/threat-feeds"
    do
        [[ -d "$d" ]] && chmod 755 "$d"
    done

    # Fix file permissions for Docker containers to read
    find "${REDELK_PATH}/elkserver" -type f -name '*.yml' -exec chmod 644 {} + 2>/dev/null || true
    find "${REDELK_PATH}/elkserver" -type f -name '*.conf' -exec chmod 644 {} + 2>/dev/null || true
    find "${REDELK_PATH}/elkserver" -type f -name '*.json' -exec chmod 644 {} + 2>/dev/null || true
    find "${REDELK_PATH}/elkserver" -type f -name '.env' -exec chmod 644 {} + 2>/dev/null || true
    find "${REDELK_PATH}/certs" -type f -name '*.crt' -exec chmod 644 {} + 2>/dev/null || true

    # Keep private keys secure
    chmod 600 "${REDELK_PATH}/certs/elkserver.key" "${REDELK_PATH}/certs/redelkCA.key" 2>/dev/null || true
    chmod 600 "${REDELK_PATH}/certs/sshkey" 2>/dev/null || true

    # Elasticsearch data directory needs to be owned by uid 1000
    chown -R 1000:1000 "${REDELK_PATH}/elasticsearch-data"

    echo "[INFO] Permissions fixed for uid 1000 (elasticsearch user)"
}

create_env_file() {
    echo "[INFO] Creating environment file..."
    cat > "${REDELK_PATH}/elkserver/docker/.env" <<EOF
REDELK_PATH=${REDELK_PATH}
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
ES_JAVA_OPTS=${ES_JAVA_OPTS}
COMPOSE_PROJECT_NAME=redelk
EOF
    chmod 644 "${REDELK_PATH}/elkserver/docker/.env"
}

create_docker_compose() {
    echo "[INFO] Creating Docker Compose configuration..."
    cat > "${REDELK_PATH}/elkserver/docker/docker-compose.yml" <<'EOF'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.15.3
    container_name: redelk-elasticsearch
    restart: unless-stopped
    environment:
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=false
      - xpack.security.authc.api_key.enabled=true
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - ES_JAVA_OPTS=${ES_JAVA_OPTS}
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - ${REDELK_PATH}/elasticsearch-data:/usr/share/elasticsearch/data
    ports:
      - "127.0.0.1:9200:9200"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS -u elastic:${ELASTIC_PASSWORD} 'http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=1s' || exit 1"]
      interval: 10s
      timeout: 10s
      retries: 60
      start_period: 90s
    networks: [redelk]

  logstash:
    image: docker.elastic.co/logstash/logstash:8.15.3
    container_name: redelk-logstash
    restart: unless-stopped
    environment:
      - xpack.monitoring.enabled=false
      - LS_JAVA_OPTS=-Xmx1g -Xms1g
    volumes:
      - ${REDELK_PATH}/elkserver/logstash/pipelines:/usr/share/logstash/pipeline:ro
    ports:
      - "0.0.0.0:5044:5044"
      - "127.0.0.1:9600:9600"
    depends_on:
      elasticsearch:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "netstat -tln | grep -q ':5044' || ss -tln | grep -q ':5044' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 40
      start_period: 60s
    networks: [redelk]

  kibana:
    image: docker.elastic.co/kibana/kibana:8.15.3
    container_name: redelk-kibana
    restart: unless-stopped
    volumes:
      - ${REDELK_PATH}/elkserver/kibana/kibana.yml:/usr/share/kibana/config/kibana.yml:ro
    ports:
      - "127.0.0.1:5601:5601"
    depends_on:
      elasticsearch:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:5601/api/status | grep -q '\"level\":\"available\"'"]
      interval: 15s
      timeout: 10s
      retries: 80
      start_period: 180s
    networks: [redelk]

  nginx:
    image: nginx:alpine
    container_name: redelk-nginx
    restart: unless-stopped
    volumes:
      - ${REDELK_PATH}/elkserver/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ${REDELK_PATH}/certs:/etc/nginx/certs:ro
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      kibana:
        condition: service_started
    networks: [redelk]

networks:
  redelk:
    driver: bridge
EOF
    chmod 644 "${REDELK_PATH}/elkserver/docker/docker-compose.yml"
}

create_nginx_config() {
    echo "[INFO] Creating Nginx configuration..."
    cat > "${REDELK_PATH}/elkserver/nginx/nginx.conf" <<'EOF'
events { worker_connections 1024; }

http {
  upstream kibana { server kibana:5601; }

  server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
  }

  server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate     /etc/nginx/certs/elkserver.crt;
    ssl_certificate_key /etc/nginx/certs/elkserver.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
      proxy_pass http://kibana;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_cache_bypass $http_upgrade;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_buffering off;
    }
  }
}
EOF

    # Fix permissions so Nginx container can read it
    chmod 644 "${REDELK_PATH}/elkserver/nginx/nginx.conf"
}

create_logstash_pipeline() {
    echo "[INFO] Creating Logstash pipeline..."
    cat > "${REDELK_PATH}/elkserver/logstash/pipelines/main.conf" <<'EOF'
input {
  beats {
    port => 5044
    ssl  => false
  }
}

filter {
  # Route to correct index based on logtype/infralogtype fields
  if [logtype] == "rtops" or [fields][logtype] == "rtops" {
    mutate { add_field => { "[@metadata][index_prefix]" => "rtops" } }
  } else if [infralogtype] == "redirtraffic" or [fields][infralogtype] == "redirtraffic" {
    mutate { add_field => { "[@metadata][index_prefix]" => "redirtraffic" } }
  } else if [infralogtype] == "redirerror" or [fields][infralogtype] == "redirerror" {
    mutate { add_field => { "[@metadata][index_prefix]" => "redirerror" } }
  } else if [infralogtype] == "c2" or [fields][infralogtype] == "c2" {
    mutate { add_field => { "[@metadata][index_prefix]" => "rtops" } }
  } else {
    mutate { add_field => { "[@metadata][index_prefix]" => "redelk" } }
  }
}

output {
  elasticsearch {
    hosts    => ["http://elasticsearch:9200"]
    user     => "elastic"
    password => "RedElk2024Secure"
    index    => "%{[@metadata][index_prefix]}-%{+YYYY.MM.dd}"
    template_overwrite => true
  }
}
EOF

    # Fix permissions so Logstash container (uid 1000) can read it
    chmod 644 "${REDELK_PATH}/elkserver/logstash/pipelines/main.conf"
}

provision_logstash_api_key() {
    echo "[INFO] Creating Logstash API key (writer)..."
    local resp
    resp="$(curl -sS -u "elastic:${ELASTIC_PASSWORD}" \
        -H 'Content-Type: application/json' \
        -X POST "http://127.0.0.1:9200/_security/api_key" \
        -d '{
          "name": "redelk-logstash-writer",
          "role_descriptors": {
            "logstash_writer": {
              "cluster": ["manage_index_templates", "monitor"],
              "index": [{
                "names": ["redelk-*","rtops-*","redirtraffic-*","alarms-*"],
                "privileges": ["create_index","write","create"]
              }]
            }
          }
        }')"
    export LS_ES_API_KEY="$(echo "$resp" | jq -r '.encoded' )"
    if [[ -z "$LS_ES_API_KEY" || "$LS_ES_API_KEY" == "null" ]]; then
        echo "[ERROR] Failed to create API key for Logstash"
        echo "$resp"
        exit 1
    fi

    # Persist to .env for systemd restarts
    sed -i "/^LS_ES_API_KEY=/d" "${REDELK_PATH}/elkserver/docker/.env" 2>/dev/null || true
    printf "LS_ES_API_KEY=%s\n" "$LS_ES_API_KEY" >> "${REDELK_PATH}/elkserver/docker/.env"

    echo "[INFO] LS_ES_API_KEY created and persisted to .env"
}

provision_kibana_service_token() {
    echo "[INFO] Provisioning Kibana service account token and config..."
    mkdir -p "${KIBANA_CONFIG_DIR}"
    local token_file="${KIBANA_CONFIG_DIR}/.service_token"
    local token=""

    if [[ -f "$token_file" ]]; then
        token="$(cat "$token_file")"
        if curl -sS -H "Authorization: Bearer ${token}" http://127.0.0.1:9200/_security/_authenticate >/dev/null 2>&1; then
            echo "[INFO] Reusing existing Kibana service token"
        else
            token=""
            echo "[WARN] Existing service token invalid; creating a new one"
        fi
    fi

    if [[ -z "$token" ]]; then
        # Delete existing token to ensure idempotency
        curl -sS -u "elastic:${ELASTIC_PASSWORD}" \
            -X DELETE "http://127.0.0.1:9200/_security/service/elastic/kibana/credential/token/redelk" >/dev/null 2>&1 || true

        local resp
        resp="$(curl -sS -u "elastic:${ELASTIC_PASSWORD}" \
            -H 'Content-Type: application/json' \
            -X POST "http://127.0.0.1:9200/_security/service/elastic/kibana/credential/token/redelk")"
        token="$(echo "$resp" | jq -r '.token.value')"
        if [[ -z "$token" || "$token" == "null" ]]; then
            echo "[ERROR] Failed to create Kibana service account token"
            echo "$resp"
            exit 1
        fi
        echo "$token" > "$token_file"
        chmod 600 "$token_file"
        echo "[INFO] Created new Kibana service token"
    fi

    local server_ip
    server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -z "$server_ip" ]] && server_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
    [[ -z "$server_ip" ]] && server_ip="127.0.0.1"

    cat > "${KIBANA_CONFIG_DIR}/kibana.yml" <<EOF
server.name: "kibana"
server.host: "0.0.0.0"
server.publicBaseUrl: "https://${server_ip}"
elasticsearch.hosts: ["http://elasticsearch:9200"]
elasticsearch.serviceAccountToken: "${token}"
telemetry.enabled: false
logging.root.level: "warn"
EOF
    chown 1000:0 "${KIBANA_CONFIG_DIR}/kibana.yml" || true
    chmod 640 "${KIBANA_CONFIG_DIR}/kibana.yml" || true
    echo "[INFO] Kibana config created with proper permissions (owner: 1000:0, mode: 640)"
}

create_systemd_service() {
    echo "[INFO] Creating systemd service..."
    cat > /etc/systemd/system/redelk.service <<EOF
[Unit]
Description=RedELK Stack
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${REDELK_PATH}/elkserver/docker
Environment="REDELK_PATH=${REDELK_PATH}"
Environment="ELASTIC_PASSWORD=${ELASTIC_PASSWORD}"
Environment="ES_JAVA_OPTS=${ES_JAVA_OPTS}"
EnvironmentFile=${REDELK_PATH}/elkserver/docker/.env
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable redelk
}

open_firewall() {
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        echo "[INFO] UFW: opened 80/tcp and 443/tcp"
    fi
}

start_stack() {
    echo ""
    echo "========================================"
    echo "DEPLOYING REDELK STACK"
    echo "========================================"
    echo ""

    cd "${REDELK_PATH}/elkserver/docker"
    $COMPOSE_CMD down 2>/dev/null || true

    echo "[INFO] Pulling Docker images..."
    $COMPOSE_CMD pull

    echo ""
    echo "[INFO] Starting Elasticsearch..."
    $COMPOSE_CMD up -d elasticsearch

    echo -n "[INFO] Waiting for Elasticsearch to be ready (this may take 3-6 minutes)"
    local code
    local ok=false
    for ((i=1;i<=120;i++)); do
        code="$(curl -sS -u "elastic:${ELASTIC_PASSWORD}" -o /dev/null -w '%{http_code}' http://127.0.0.1:9200/_cluster/health || true)"
        if [[ "$code" == "200" ]]; then ok=true; break; fi
        sleep 3; echo -n "."
    done
    echo " ✓"

    if [[ "$ok" != "true" ]]; then
        echo ""
        echo "[ERROR] Elasticsearch failed to start"
        echo "[ERROR] Last 50 lines of logs:"
        docker logs --tail=50 redelk-elasticsearch || true
        exit 1
    fi

    echo "[INFO] Elasticsearch is healthy"

    # No longer using API key authentication - using basic auth instead
    # provision_logstash_api_key
    provision_kibana_service_token

    echo ""
    echo "[INFO] Starting Logstash..."
    $COMPOSE_CMD up -d logstash

    # Give Logstash initial time to start JVM
    sleep 10

    echo -n "[INFO] Waiting for Logstash to be ready (checking logs for port 5044)"
    ok=false
    for ((i=1;i<=120;i++)); do
        # Check container logs for the actual "Starting server on port: 5044" message
        if docker logs redelk-logstash 2>&1 | grep -q "Starting server on port: 5044"; then
            ok=true
            break
        fi
        sleep 3; echo -n "."
    done
    echo " ✓"

    if [[ "$ok" != "true" ]]; then
        echo ""
        echo "[ERROR] Logstash failed to start within 2 minutes"
        echo "[ERROR] Did not see 'Starting server on port: 5044' in logs"
        echo "[ERROR] Container logs:"
        docker logs redelk-logstash 2>&1 | tail -50
        exit 1
    fi

    echo "[INFO] Logstash is healthy and ready to receive data on port 5044"

    echo ""
    echo "[INFO] Starting Kibana..."
    $COMPOSE_CMD up -d kibana

    echo -n "[INFO] Waiting for Kibana to be ready (this may take 5-10 minutes on first boot)"
    ok=false
    for ((i=1;i<=120;i++)); do
        if curl -sS http://127.0.0.1:5601/api/status 2>/dev/null | grep -q '"level":"available"'; then
            ok=true
            break
        fi
        sleep 5; echo -n "."
    done
    echo " ✓"

    if [[ "$ok" != "true" ]]; then
        echo ""
        echo "[ERROR] Kibana failed to start within 10 minutes"
        echo "[ERROR] Last 50 lines of logs:"
        docker logs --tail=50 redelk-kibana || true
        echo ""
        echo "[ERROR] This usually indicates insufficient resources or container issues"
        echo "[ERROR] Check: docker logs redelk-kibana"
        exit 1
    fi

    echo "[INFO] Kibana is ready and healthy"

    echo ""
    echo "[INFO] Starting Nginx..."
    $COMPOSE_CMD up -d nginx
    sleep 3

    if docker exec redelk-nginx nginx -t >/dev/null 2>&1; then
        echo "[INFO] Nginx configuration valid"
    else
        echo "[ERROR] Nginx configuration invalid"
        docker exec redelk-nginx nginx -t
        exit 1
    fi

    echo ""
    echo "[INFO] All services started"
    echo "========================================"
    echo ""
}

deploy_elasticsearch_templates() {
    echo "[INFO] Deploying Elasticsearch index templates..."
    sleep 2

    for template in rtops redirtraffic alarms; do
        if [[ -f "${REDELK_PATH}/elkserver/elasticsearch/index-templates/${template}-template.json" ]]; then
            echo "[INFO] Creating ${template} index template..."
            curl -sS -u "elastic:${ELASTIC_PASSWORD}" \
                -H "Content-Type: application/json" \
                -X PUT "http://127.0.0.1:9200/_index_template/${template}" \
                -d @"${REDELK_PATH}/elkserver/elasticsearch/index-templates/${template}-template.json" >/dev/null || {
                    echo "[WARN] Failed to create ${template} template"
                }
        fi
    done
}

deploy_logstash_configs() {
    echo "[INFO] Deploying Logstash pipeline configurations..."
    mkdir -p "${REDELK_PATH}/elkserver/logstash/pipelines"
    chmod 755 "${REDELK_PATH}/elkserver/logstash/pipelines"

    if ls "${REDELK_PATH}/elkserver/logstash/conf.d/"*.conf >/dev/null 2>&1; then
        cp "${REDELK_PATH}/elkserver/logstash/conf.d/"*.conf "${REDELK_PATH}/elkserver/logstash/pipelines/" || true
        # Fix permissions so Logstash container (uid 1000) can read configs
        chmod 644 "${REDELK_PATH}/elkserver/logstash/pipelines/"*.conf 2>/dev/null || true
        echo "[INFO] Logstash pipeline configurations deployed"
    fi

    mkdir -p "${REDELK_PATH}/elkserver/logstash/threat-feeds"
    chmod 755 "${REDELK_PATH}/elkserver/logstash/threat-feeds"
}

deploy_kibana_dashboards() {
    echo "[INFO] Deploying Kibana dashboards and index patterns..."

    local kb_ready=false
    echo "[INFO] Waiting for Kibana API to be ready..."
    echo "[INFO] This may take 2-3 minutes on first boot..."
    for ((i=1;i<=90;i++)); do
        if curl -sS "http://127.0.0.1:5601/api/status" \
               -u "elastic:${ELASTIC_PASSWORD}" 2>/dev/null | grep -q '"level":"available"'; then
            kb_ready=true
            echo ""
            echo "[INFO] Kibana API is ready"
            break
        fi
        sleep 2
        echo -n "."
    done
    echo ""

    if [[ "$kb_ready" == "true" ]]; then
        echo "[INFO] Creating index patterns..."
        for pattern in "rtops-*" "redirtraffic-*" "alarms-*"; do
            echo "[INFO] Creating index pattern: $pattern"
            local pattern_id="${pattern/\*/}"
            curl -sS -X POST "http://127.0.0.1:5601/api/saved_objects/index-pattern/${pattern_id}" \
                -u "elastic:${ELASTIC_PASSWORD}" \
                -H "kbn-xsrf: true" \
                -H "Content-Type: application/json" \
                -d "{\"attributes\":{\"title\":\"${pattern}\",\"timeFieldName\":\"@timestamp\"}}" 2>&1 | \
                grep -q "\"id\"" && echo "[INFO] Created index pattern: $pattern" || echo "[INFO] Index pattern already exists: $pattern"
        done

        if [[ -f "${REDELK_PATH}/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson" ]]; then
            echo "[INFO] Importing Kibana dashboards..."
            local import_response
            import_response=$(curl -sS -X POST "http://127.0.0.1:5601/api/saved_objects/_import?overwrite=true" \
                -u "elastic:${ELASTIC_PASSWORD}" \
                -H "kbn-xsrf: true" \
                -F "file=@${REDELK_PATH}/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson" 2>&1)

            if echo "$import_response" | grep -q '"success":true' || echo "$import_response" | grep -q '"successCount"'; then
                echo "[INFO] Successfully imported Kibana dashboards!"
                local success_count=$(echo "$import_response" | jq -r '.successCount // .success' 2>/dev/null || echo "")
                [[ -n "$success_count" && "$success_count" != "null" ]] && echo "[INFO] Imported $success_count objects"
                echo "[INFO] Dashboard URL: https://$(hostname -I | awk '{print $1}')/app/dashboards"
            else
                echo ""
                echo "[ERROR] Dashboard import FAILED!"
                echo "[ERROR] Response from Kibana:"
                echo "$import_response" | jq '.' 2>/dev/null || echo "$import_response"
                echo ""
                echo "[ERROR] This is a critical failure - dashboards are the main feature of RedELK"
                echo "[ERROR] Check /var/log/redelk_deploy.log for full output"
                echo "[ERROR] You can retry dashboard import with: sudo bash /tmp/fix-dashboards.sh"
                exit 1
            fi
        else
            echo "[WARN] Dashboard file not found at: ${REDELK_PATH}/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson"
        fi

        echo "[INFO] Setting default index pattern..."
        curl -sS -X POST "http://127.0.0.1:5601/api/kibana/settings" \
            -u "elastic:${ELASTIC_PASSWORD}" \
            -H "kbn-xsrf: true" \
            -H "Content-Type: application/json" \
            -d '{"changes":{"defaultIndex":"rtops-*"}}' >/dev/null 2>&1 || true
    else
        echo "[WARN] Kibana not ready for dashboard import after 60 seconds"
        echo "[INFO] You can manually import dashboards later from: ${REDELK_PATH}/elkserver/kibana/dashboards/"
    fi
}

deploy_helper_scripts() {
    echo "[INFO] Deploying helper scripts..."
    mkdir -p "${REDELK_PATH}/scripts"

    if ls "${REDELK_PATH}/scripts/"*.sh >/dev/null 2>&1; then
        chmod +x "${REDELK_PATH}/scripts/"*.sh
        echo "[INFO] Helper scripts deployed to ${REDELK_PATH}/scripts/"
    fi

    if [[ -f "${REDELK_PATH}/scripts/update-threat-feeds.sh" ]]; then
        echo "[INFO] Setting up threat feed update cron job..."
        (crontab -l 2>/dev/null | grep -v "update-threat-feeds.sh" ; \
         echo "0 */6 * * * ${REDELK_PATH}/scripts/update-threat-feeds.sh >/dev/null 2>&1") | crontab - || {
            echo "[WARN] Failed to setup threat feed cron job"
        }
    fi
}

create_deployment_packages() {
    echo "[INFO] Creating deployment packages..."

    local server_ip
    # Try multiple methods to detect the primary IP
    server_ip="$(ip -4 route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[\d.]+')"
    [[ -z "$server_ip" ]] && server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -z "$server_ip" ]] && server_ip="$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)"
    [[ -z "$server_ip" ]] && server_ip="$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)"

    if [ -z "$server_ip" ] || [ "$server_ip" = "127.0.0.1" ]; then
        echo "[ERROR] Could not detect server IP"
        echo "[INFO] Available network interfaces:"
        ip -4 addr show | grep -E "inet\s" || true
        echo ""
        echo "[WARN] Packages will contain placeholder - you must replace REDELK_SERVER_IP manually"
        server_ip="REDELK_SERVER_IP"
    else
        echo "[INFO] Detected server IP: $server_ip"
    fi

    local c2_pkg="${REDELK_PATH}/c2package"
    mkdir -p "${c2_pkg}"

    if [[ -f "${REDELK_PATH}/certs/redelkCA.crt" ]]; then
        cp "${REDELK_PATH}/certs/redelkCA.crt" "${c2_pkg}/"
    fi
    if [[ -f "${REDELK_PATH}/certs/sshkey" ]]; then
        cp "${REDELK_PATH}/certs/sshkey" "${c2_pkg}/"
    fi

    mkdir -p "${c2_pkg}/filebeat"

    # Copy existing configs if available
    local config_count=0
    if ls "${REDELK_PATH}/c2servers/"*.yml >/dev/null 2>&1; then
        for config in "${REDELK_PATH}/c2servers/"*.yml; do
            local filename=$(basename "$config")
            if [[ "$server_ip" != "REDELK_SERVER_IP" ]]; then
                sed "s/REDELK_SERVER_IP/${server_ip}/g" "$config" > "${c2_pkg}/filebeat/${filename}"
                echo "[INFO] Updated $filename with server IP: $server_ip"
            else
                cp "$config" "${c2_pkg}/filebeat/${filename}"
                echo "[WARN] Using placeholder in $filename - update manually with actual IP"
            fi
            ((config_count++))
        done
    fi

    # If no configs found, create default ones
    if [[ $config_count -eq 0 ]]; then
        echo "[WARN] No filebeat configs found in ${REDELK_PATH}/c2servers/, creating defaults..."

        # Create Cobalt Strike config
        cat > "${c2_pkg}/filebeat/filebeat-cobaltstrike.yml" <<'FBEOF'
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /opt/cobaltstrike/logs/*/beacon_*.log
    - /opt/cobaltstrike/server/logs/*/beacon_*.log
    - /home/*/cobaltstrike/*/server/logs/*/beacon_*.log
    - /opt/cobaltstrike/logs/*/events.log
    - /opt/cobaltstrike/server/logs/*/events.log
    - /home/*/cobaltstrike/*/server/logs/*/events.log
    - /opt/cobaltstrike/logs/*/weblog.log
    - /opt/cobaltstrike/server/logs/*/weblog.log
    - /home/*/cobaltstrike/*/server/logs/*/weblog.log
    - /opt/cobaltstrike/logs/*/downloads.log
    - /opt/cobaltstrike/server/logs/*/downloads.log
    - /home/*/cobaltstrike/*/server/logs/*/downloads.log
    - /opt/cobaltstrike/logs/*/keystrokes.log
    - /opt/cobaltstrike/server/logs/*/keystrokes.log
    - /home/*/cobaltstrike/*/server/logs/*/keystrokes.log
    - /opt/cobaltstrike/logs/*/screenshots.log
    - /opt/cobaltstrike/server/logs/*/screenshots.log
    - /home/*/cobaltstrike/*/server/logs/*/screenshots.log
  fields:
    logtype: rtops
    c2_program: cobaltstrike
    infralogtype: c2
  fields_under_root: false
  multiline.pattern: '^\d{2}/\d{2} \d{2}:\d{2}:\d{2}'
  multiline.negate: true
  multiline.match: after

output.logstash:
  hosts: ["REDELK_SERVER_IP:5044"]
  ssl.enabled: false
  bulk_max_size: 2048

processors:
  - add_host_metadata: ~
  - add_fields:
      target: ''
      fields:
        attack_scenario: "${SCENARIO_NAME:default}"

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  keepfiles: 7
FBEOF
        # Replace IP placeholder
        sed -i "s/REDELK_SERVER_IP/${server_ip}/g" "${c2_pkg}/filebeat/filebeat-cobaltstrike.yml"

        # Create PoshC2 config
        cat > "${c2_pkg}/filebeat/filebeat-poshc2.yml" <<'FBEOF'
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/poshc2/*/database.db.log
    - /var/poshc2/*/implant_logs/*.log
  fields:
    logtype: rtops
    c2_program: poshc2
    infralogtype: c2
  fields_under_root: false

output.logstash:
  hosts: ["REDELK_SERVER_IP:5044"]
  ssl.enabled: false

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  keepfiles: 7
FBEOF
        # Replace IP placeholder
        sed -i "s/REDELK_SERVER_IP/${server_ip}/g" "${c2_pkg}/filebeat/filebeat-poshc2.yml"

        echo "[INFO] Created default filebeat configs with IP: ${server_ip}"
    fi

    cat > "${c2_pkg}/deploy-filebeat-c2.sh" <<'EOF'
#!/bin/bash
echo "Deploying RedELK filebeat agent for C2 server..."

# Clean up previous installation
echo "[INFO] Cleaning up previous Filebeat installation..."
systemctl stop filebeat 2>/dev/null || true
systemctl disable filebeat 2>/dev/null || true

# Backup and remove old config
if [[ -f /etc/filebeat/filebeat.yml ]]; then
    cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.backup.$(date +%s) 2>/dev/null || true
fi

# Remove old data and registry
rm -rf /var/lib/filebeat/registry 2>/dev/null || true
rm -rf /var/log/filebeat/* 2>/dev/null || true

# Install or update Filebeat
ARCH="$(dpkg --print-architecture)"
DEB="filebeat-8.15.3-${ARCH}.deb"

if ! command -v filebeat &>/dev/null; then
    echo "[INFO] Installing Filebeat..."
    curl -fL -O "https://artifacts.elastic.co/downloads/beats/filebeat/${DEB}"
    dpkg -i "${DEB}" || apt-get -y -qq install "./${DEB}"
    rm -f "${DEB}"
else
    echo "[INFO] Filebeat already installed"
fi

cp filebeat/filebeat-cobaltstrike.yml /etc/filebeat/filebeat.yml

[[ -f redelkCA.crt ]] && mkdir -p /etc/filebeat/certs && cp redelkCA.crt /etc/filebeat/certs/
[[ -f sshkey ]] && cp sshkey /etc/filebeat/certs/ && chmod 600 /etc/filebeat/certs/sshkey

CS_PATH="/opt/cobaltstrike"
if [[ -d "$CS_PATH/logs" ]]; then
    sed -i "s|/opt/cobaltstrike/logs|$CS_PATH/logs|g" /etc/filebeat/filebeat.yml
elif [[ -d "$CS_PATH/server/logs" ]]; then
    sed -i "s|/opt/cobaltstrike/logs|$CS_PATH/server/logs|g" /etc/filebeat/filebeat.yml
fi

chmod 600 /etc/filebeat/filebeat.yml
filebeat test config || exit 1
systemctl enable filebeat
systemctl restart filebeat

echo "Filebeat deployment complete!"
echo "Check status: systemctl status filebeat"
EOF

    chmod +x "${c2_pkg}/deploy-filebeat-c2.sh"
    tar czf "${REDELK_PATH}/c2servers.tgz" -C "${REDELK_PATH}" c2package
    chmod 644 "${REDELK_PATH}/c2servers.tgz"

    # Make accessible: copy to /tmp for easy download
    cp "${REDELK_PATH}/c2servers.tgz" /tmp/c2servers.tgz
    chmod 644 /tmp/c2servers.tgz

    rm -rf "${c2_pkg}"

    local redir_pkg="${REDELK_PATH}/redirpackage"
    mkdir -p "${redir_pkg}"

    if [[ -f "${REDELK_PATH}/certs/redelkCA.crt" ]]; then
        cp "${REDELK_PATH}/certs/redelkCA.crt" "${redir_pkg}/"
    fi
    if [[ -f "${REDELK_PATH}/certs/elkserver.crt" ]]; then
        cp "${REDELK_PATH}/certs/elkserver.crt" "${redir_pkg}/"
    fi

    mkdir -p "${redir_pkg}/filebeat"

    # Copy existing configs if available
    config_count=0
    if ls "${REDELK_PATH}/redirs/"*.yml >/dev/null 2>&1; then
        for config in "${REDELK_PATH}/redirs/"*.yml; do
            local filename=$(basename "$config")
            if [[ "$server_ip" != "REDELK_SERVER_IP" ]]; then
                sed "s/REDELK_SERVER_IP/${server_ip}/g" "$config" > "${redir_pkg}/filebeat/${filename}"
                echo "[INFO] Updated $filename with server IP: $server_ip"
            else
                cp "$config" "${redir_pkg}/filebeat/${filename}"
                echo "[WARN] Using placeholder in $filename - update manually with actual IP"
            fi
            ((config_count++))
        done
    fi

    # If no configs found, create default ones
    if [[ $config_count -eq 0 ]]; then
        echo "[WARN] No filebeat configs found in ${REDELK_PATH}/redirs/, creating defaults..."

        # Create Nginx config
        cat > "${redir_pkg}/filebeat/filebeat-nginx.yml" <<'FBEOF'
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/nginx/access.log
    - /var/log/nginx/*access*.log
  fields:
    infralogtype: redirtraffic
    redirprogram: nginx
  fields_under_root: true

output.logstash:
  hosts: ["REDELK_SERVER_IP:5044"]
  ssl.enabled: false

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  keepfiles: 7
FBEOF
        sed -i "s/REDELK_SERVER_IP/${server_ip}/g" "${redir_pkg}/filebeat/filebeat-nginx.yml"

        # Create Apache config
        cat > "${redir_pkg}/filebeat/filebeat-apache.yml" <<'FBEOF'
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/apache2/access.log
    - /var/log/apache2/*access*.log
    - /var/log/httpd/access_log
    - /var/log/httpd/*access*.log
  fields:
    infralogtype: redirtraffic
    redirprogram: apache
  fields_under_root: true

output.logstash:
  hosts: ["REDELK_SERVER_IP:5044"]
  ssl.enabled: false

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  keepfiles: 7
FBEOF
        sed -i "s/REDELK_SERVER_IP/${server_ip}/g" "${redir_pkg}/filebeat/filebeat-apache.yml"

        # Create HAProxy config
        cat > "${redir_pkg}/filebeat/filebeat-haproxy.yml" <<'FBEOF'
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/haproxy.log
  fields:
    infralogtype: redirtraffic
    redirprogram: haproxy
  fields_under_root: true

output.logstash:
  hosts: ["REDELK_SERVER_IP:5044"]
  ssl.enabled: false

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  keepfiles: 7
FBEOF
        sed -i "s/REDELK_SERVER_IP/${server_ip}/g" "${redir_pkg}/filebeat/filebeat-haproxy.yml"

        echo "[INFO] Created default filebeat configs with IP: ${server_ip}"
    fi

    cat > "${redir_pkg}/deploy-filebeat-redir.sh" <<'EOF'
#!/bin/bash
echo "Deploying RedELK filebeat agent for redirector..."

# Clean up previous installation
echo "[INFO] Cleaning up previous Filebeat installation..."
systemctl stop filebeat 2>/dev/null || true
systemctl disable filebeat 2>/dev/null || true

# Backup and remove old config
if [[ -f /etc/filebeat/filebeat.yml ]]; then
    cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.backup.$(date +%s) 2>/dev/null || true
fi

# Remove old data and registry
rm -rf /var/lib/filebeat/registry 2>/dev/null || true
rm -rf /var/log/filebeat/* 2>/dev/null || true

# Install or update Filebeat
ARCH="$(dpkg --print-architecture)"
DEB="filebeat-8.15.3-${ARCH}.deb"

if ! command -v filebeat &>/dev/null; then
    echo "[INFO] Installing Filebeat..."
    curl -fL -O "https://artifacts.elastic.co/downloads/beats/filebeat/${DEB}"
    dpkg -i "${DEB}" || apt-get -y -qq install "./${DEB}"
    rm -f "${DEB}"
else
    echo "[INFO] Filebeat already installed"
fi

cp filebeat/filebeat-nginx.yml /etc/filebeat/filebeat.yml

[[ -f redelkCA.crt ]] && mkdir -p /etc/filebeat/certs && cp redelkCA.crt /etc/filebeat/certs/
[[ -f elkserver.crt ]] && mkdir -p /etc/filebeat/certs && cp elkserver.crt /etc/filebeat/certs/

chmod 600 /etc/filebeat/filebeat.yml
filebeat test config || exit 1
systemctl enable filebeat
systemctl restart filebeat

echo "Filebeat deployment complete!"
echo "Check status: systemctl status filebeat"
echo "View logs: journalctl -u filebeat -f"
EOF

    chmod +x "${redir_pkg}/deploy-filebeat-redir.sh"
    tar czf "${REDELK_PATH}/redirs.tgz" -C "${REDELK_PATH}" redirpackage
    chmod 644 "${REDELK_PATH}/redirs.tgz"

    # Make accessible: copy to /tmp for easy download
    cp "${REDELK_PATH}/redirs.tgz" /tmp/redirs.tgz
    chmod 644 /tmp/redirs.tgz

    rm -rf "${redir_pkg}"

    echo "[INFO] Deployment packages created:"
    echo "  C2 Servers: ${REDELK_PATH}/c2servers.tgz (also at /tmp/c2servers.tgz)"
    echo "  Redirectors: ${REDELK_PATH}/redirs.tgz (also at /tmp/redirs.tgz)"
    echo ""
    if [[ "$server_ip" == "REDELK_SERVER_IP" ]]; then
        echo "[WARN] Using placeholder IP - update filebeat configs manually"
    else
        echo "[INFO] Server IP configured: $server_ip"
    fi
}

print_summary() {
    local server_ip
    server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -z "$server_ip" ]] && server_ip="$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)"

    echo ""
    echo "========================================"
    echo "FINAL STATUS CHECK"
    echo "========================================"
    echo ""

    echo "Docker Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=redelk"
    echo ""

    local RUNNING=$(docker ps --filter "name=redelk" --format "{{.Names}}" | wc -l)
    echo "Running: $RUNNING/4 services"

    if [ "$RUNNING" -ne 4 ]; then
        echo ""
        echo "[ERROR] MISSING SERVICES - Checking why:"
        for s in redelk-elasticsearch redelk-logstash redelk-kibana redelk-nginx; do
            if ! docker ps --filter "name=${s}" --format "{{.Names}}" | grep -q "${s}"; then
                echo ""
                echo "=== $s crashed ==="
                docker logs "$s" 2>&1 | tail -30
            fi
        done
        echo ""
        echo "[ERROR] Deployment incomplete - check logs above"
        return 1
    fi

    echo ""
    echo "Testing connectivity..."
    echo ""

    echo -n "  Elasticsearch: "
    if curl -s -u "elastic:${ELASTIC_PASSWORD}" http://127.0.0.1:9200 >/dev/null 2>&1; then
        echo "✓ OK"
    else
        echo "✗ FAIL"
    fi

    echo -n "  Kibana: "
    if curl -s http://127.0.0.1:5601/api/status >/dev/null 2>&1; then
        echo "✓ OK"
    else
        echo "✗ FAIL"
    fi

    echo -n "  Nginx: "
    if curl -s -k https://127.0.0.1 >/dev/null 2>&1; then
        echo "✓ OK"
    else
        echo "✗ FAIL"
    fi

    echo -n "  Logstash (port 5044): "
    if nc -zv 127.0.0.1 5044 2>&1 | grep -q succeeded || ss -ltn | grep -q ':5044'; then
        echo "✓ OK"
    else
        echo "✗ FAIL"
    fi

    echo ""
    echo "========================================"
    echo "INSTALLATION COMPLETE"
    echo "========================================"
    echo ""
    echo "Access RedELK:"
    echo "  URL: https://${server_ip}/"
    echo "  Username: elastic"
    echo "  Password: ${ELASTIC_PASSWORD}"
    echo ""
    echo "Deployment Packages (with IP ${server_ip} configured):"
    echo "  C2 Servers: ${REDELK_PATH}/c2servers.tgz"
    echo "  Redirectors: ${REDELK_PATH}/redirs.tgz"
    echo ""
    echo "Public copies available for easy download:"
    echo "  /tmp/c2servers.tgz"
    echo "  /tmp/redirs.tgz"
    echo ""
    echo "Deploy to C2 server:"
    echo "  scp /tmp/c2servers.tgz user@c2-server:/tmp/"
    echo "  ssh user@c2-server"
    echo "  cd /tmp && tar xzf c2servers.tgz && cd c2package"
    echo "  sudo bash deploy-filebeat-c2.sh"
    echo ""
    echo "Deploy to redirector:"
    echo "  scp /tmp/redirs.tgz user@redirector:/tmp/"
    echo "  ssh user@redirector"
    echo "  cd /tmp && tar xzf redirs.tgz && cd redirpackage"
    echo "  sudo bash deploy-filebeat-redir.sh"
    echo ""
    echo "Service Management:"
    echo "  systemctl status redelk"
    echo "  systemctl restart redelk"
    echo "  docker logs redelk-elasticsearch"
    echo "  docker logs redelk-kibana"
    echo "  docker logs redelk-logstash"
    echo "  docker logs redelk-nginx"
    echo ""
    echo "Helper Scripts:"
    echo "  ${REDELK_PATH}/scripts/redelk-health-check.sh"
    echo "  ${REDELK_PATH}/scripts/verify-deployment.sh"
    echo "  ${REDELK_PATH}/scripts/test-data-generator.sh"
    echo ""
    echo "Installation log: ${LOG_FILE}"
    echo "========================================"
    echo ""
}

main() {
    print_banner
    check_root
    print_facts
    check_ubuntu
    install_dependencies
    install_docker
    setup_kernel
    cleanup_existing_deployment
    create_directories
    copy_deployment_files
    generate_certificates
    fix_permissions
    create_env_file
    create_docker_compose
    create_nginx_config
    create_logstash_pipeline
    deploy_logstash_configs
    fix_permissions  # Fix permissions again after all config files are created
    create_systemd_service
    open_firewall
    start_stack
    deploy_elasticsearch_templates
    deploy_kibana_dashboards
    deploy_helper_scripts
    create_deployment_packages
    print_summary
}

main "$@"
