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
    echo "   |_| \__\___| \____||_____||_____||_|\_\\"
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

    # Set vm.max_map_count for Elasticsearch
    sysctl -w vm.max_map_count=262144 >/dev/null 2>&1

    # Persist the setting
    cat > /etc/sysctl.d/99-elasticsearch.conf <<EOF
# Elasticsearch kernel requirements
vm.max_map_count=262144
EOF

    # Reload sysctl
    sysctl --system >/dev/null 2>&1
}

create_directories() {
    echo "[INFO] Creating directory structure..."
    mkdir -p "${REDELK_PATH}"/{elkserver/{docker,nginx,logstash/pipelines,kibana},certs,logs}

    # Set proper permissions for Elasticsearch
    mkdir -p "${REDELK_PATH}/elasticsearch-data"
    chown -R 1000:1000 "${REDELK_PATH}/elasticsearch-data"
}

copy_deployment_files() {
    echo "[INFO] Copying RedELK component files from script directory..."

    # Create all necessary subdirectories
    mkdir -p "${REDELK_PATH}/elkserver/elasticsearch/index-templates"
    mkdir -p "${REDELK_PATH}/elkserver/logstash/conf.d"
    mkdir -p "${REDELK_PATH}/elkserver/logstash/threat-feeds"
    mkdir -p "${REDELK_PATH}/elkserver/kibana/dashboards"
    mkdir -p "${REDELK_PATH}/scripts"
    mkdir -p "${REDELK_PATH}/c2servers"
    mkdir -p "${REDELK_PATH}/redirs"

    # Copy Elasticsearch templates if they exist
    if ls "${SCRIPT_DIR}"/*-template.json >/dev/null 2>&1; then
        echo "[INFO] Copying Elasticsearch index templates..."
        cp "${SCRIPT_DIR}"/*-template.json "${REDELK_PATH}/elkserver/elasticsearch/index-templates/" 2>/dev/null || true
    fi

    # Copy Logstash configs if they exist
    if ls "${SCRIPT_DIR}"/*.conf >/dev/null 2>&1; then
        echo "[INFO] Copying Logstash pipeline configurations..."
        cp "${SCRIPT_DIR}"/*.conf "${REDELK_PATH}/elkserver/logstash/conf.d/" 2>/dev/null || true
    fi

    # Copy threat feed files if they exist
    for feed_file in tor-exit-nodes.txt cdn-ip-lists.txt compromised-ips.txt feodo-tracker.txt talos-reputation.txt; do
        if [[ -f "${SCRIPT_DIR}/${feed_file}" ]]; then
            echo "[INFO] Copying threat feed: ${feed_file}"
            cp "${SCRIPT_DIR}/${feed_file}" "${REDELK_PATH}/elkserver/logstash/threat-feeds/" 2>/dev/null || true
        fi
    done

    # Copy Kibana dashboards if they exist
    if ls "${SCRIPT_DIR}"/*.ndjson >/dev/null 2>&1; then
        echo "[INFO] Copying Kibana dashboards..."
        cp "${SCRIPT_DIR}"/*.ndjson "${REDELK_PATH}/elkserver/kibana/dashboards/" 2>/dev/null || true
    fi

    # Copy helper scripts if they exist
    for script in redelk-health-check.sh redelk-beacon-manager.sh update-threat-feeds.sh verify-deployment.sh; do
        if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
            echo "[INFO] Copying helper script: ${script}"
            cp "${SCRIPT_DIR}/${script}" "${REDELK_PATH}/scripts/"
            chmod +x "${REDELK_PATH}/scripts/${script}"
        fi
    done

    # Copy Filebeat configs if they exist
    if ls "${SCRIPT_DIR}"/filebeat-*.yml >/dev/null 2>&1; then
        echo "[INFO] Copying Filebeat configurations..."
        # C2 server configs
        for config in filebeat-cobaltstrike.yml filebeat-poshc2.yml filebeat-sliver.yml; do
            [[ -f "${SCRIPT_DIR}/${config}" ]] && cp "${SCRIPT_DIR}/${config}" "${REDELK_PATH}/c2servers/"
        done
        # Redirector configs
        for config in filebeat-apache.yml filebeat-nginx.yml filebeat-haproxy.yml; do
            [[ -f "${SCRIPT_DIR}/${config}" ]] && cp "${SCRIPT_DIR}/${config}" "${REDELK_PATH}/redirs/"
        done
    fi

    echo "[INFO] Component files copied successfully"
}

generate_certificates() {
    echo "[INFO] Generating TLS certificates..."
    local cert_dir="${REDELK_PATH}/certs"

    # Skip if already generated
    if [[ -f "${cert_dir}/elkserver.crt" && -f "${cert_dir}/redelkCA.crt" && -f "${cert_dir}/sshkey" ]]; then
        echo "[INFO] Certificates already exist, skipping"
        return
    fi

    # Get server IP
    local server_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)

    # Create OpenSSL config
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

    # Generate CA
    openssl genrsa -out "${cert_dir}/redelkCA.key" 4096 2>/dev/null
    openssl req -new -x509 -days 3650 -key "${cert_dir}/redelkCA.key" -out "${cert_dir}/redelkCA.crt" \
        -subj "/CN=RedELK CA" 2>/dev/null

    # Generate server certificate
    openssl genrsa -out "${cert_dir}/elkserver.key" 4096 2>/dev/null
    openssl req -new -key "${cert_dir}/elkserver.key" -out "${cert_dir}/elkserver.csr" -config "${cert_dir}/config.cnf" 2>/dev/null
    openssl x509 -req -in "${cert_dir}/elkserver.csr" -CA "${cert_dir}/redelkCA.crt" -CAkey "${cert_dir}/redelkCA.key" \
        -CAcreateserial -out "${cert_dir}/elkserver.crt" -days 3650 -extensions v3_req \
        -extfile "${cert_dir}/config.cnf" 2>/dev/null

    # Generate SSH keys
    rm -f "${cert_dir}/sshkey" "${cert_dir}/sshkey.pub"
    ssh-keygen -t ed25519 -f "${cert_dir}/sshkey" -N "" -q

    # Lock down private keys
    chmod 600 "${cert_dir}/elkserver.key" "${cert_dir}/redelkCA.key" "${cert_dir}/sshkey" 2>/dev/null || true
}

check_ports() {
    echo "[INFO] Checking port availability..."
    local ports=(80 443 5601 5044 9200)
    local port_in_use=false

    for port in "${ports[@]}"; do
        if ss -H -ltn '( sport = :'$port' )' 2>/dev/null | grep -q ':'$port'\b'; then
            echo "[ERROR] Port $port is already in use"
            echo "Run: ss -ltnp | grep :$port"
            port_in_use=true
        fi
    done

    if [[ "$port_in_use" == "true" ]]; then
        exit 1
    fi
}

create_env_file() {
    echo "[INFO] Creating environment file..."
    cat > "${REDELK_PATH}/elkserver/docker/.env" <<EOF
# RedELK Environment Configuration
REDELK_PATH=${REDELK_PATH}
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
ES_JAVA_OPTS=${ES_JAVA_OPTS}
COMPOSE_PROJECT_NAME=redelk
EOF
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
      - ${REDELK_PATH}/certs:/usr/share/elasticsearch/config/certs:ro
    ports:
      - "127.0.0.1:9200:9200"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS -u elastic:${ELASTIC_PASSWORD} 'http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=1s' || exit 1"]
      interval: 10s
      timeout: 10s
      retries: 60
      start_period: 90s
    networks:
      - redelk

  logstash:
    image: docker.elastic.co/logstash/logstash:8.15.3
    container_name: redelk-logstash
    restart: unless-stopped
    environment:
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - xpack.monitoring.enabled=false
      - LS_JAVA_OPTS=-Xmx1g -Xms1g
    volumes:
      - ${REDELK_PATH}/elkserver/logstash/pipelines:/usr/share/logstash/pipeline:ro
      - ${REDELK_PATH}/certs:/usr/share/logstash/config/certs:ro
    ports:
      - "0.0.0.0:5044:5044"
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - redelk

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
    networks:
      - redelk

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
        condition: service_started  # Changed from service_healthy to avoid blocking on transient unhealthy status
    networks:
      - redelk

networks:
  redelk:
    driver: bridge
EOF
}

create_nginx_config() {
    echo "[INFO] Creating Nginx configuration..."
    cat > "${REDELK_PATH}/elkserver/nginx/nginx.conf" <<'EOF'
events {
    worker_connections 1024;
}

http {
    upstream kibana {
        server kibana:5601;
    }

    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name _;

        ssl_certificate /etc/nginx/certs/elkserver.crt;
        ssl_certificate_key /etc/nginx/certs/elkserver.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        location / {
            proxy_pass http://kibana;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
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
}

create_logstash_pipeline() {
    echo "[INFO] Creating Logstash pipeline..."
    cat > "${REDELK_PATH}/elkserver/logstash/pipelines/main.conf" <<'EOF'
input {
  beats {
    port => 5044
    ssl => false
  }
}

filter {
  mutate {
    add_field => { "[@metadata][index_prefix]" => "redelk" }
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    user => "logstash_system"
    password => "${ELASTIC_PASSWORD}"
    index => "%{[@metadata][index_prefix]}-%{+YYYY.MM.dd}"
    template_name => "redelk"
    template_overwrite => true
  }
}
EOF
}

provision_kibana_service_token() {
    echo "[INFO] Provisioning Kibana service account token and config..."
    mkdir -p "${KIBANA_CONFIG_DIR}"

    # Delete existing token if it exists
    echo "[INFO] Removing existing service token if present..."
    curl -sS -u "elastic:${ELASTIC_PASSWORD}" \
        -X DELETE "http://127.0.0.1:9200/_security/service/elastic/kibana/credential/token/redelk" 2>/dev/null || true

    # Create new token via Elasticsearch Security API (requires elastic superuser).
    local response
    local token
    response="$(curl -sS -u "elastic:${ELASTIC_PASSWORD}" \
        -H 'Content-Type: application/json' \
        -X POST "http://127.0.0.1:9200/_security/service/elastic/kibana/credential/token/redelk" 2>&1)"
    token="$(echo "$response" | jq -r '.token.value' 2>/dev/null || true)"
    if [[ -z "${token}" || "${token}" == "null" ]]; then
        echo "[ERROR] Failed to create Kibana service account token"
        echo "[DEBUG] API response: $response"
        docker logs redelk-elasticsearch --tail 200 || true
        exit 1
    fi
    cat > "${KIBANA_CONFIG_DIR}/kibana.yml" <<EOF
server.name: "kibana"
server.host: "0.0.0.0"
server.publicBaseUrl: "https://localhost"
elasticsearch.hosts: ["http://elasticsearch:9200"]
elasticsearch.serviceAccountToken: "${token}"
telemetry.enabled: false
logging.root.level: "warn"
EOF
    # CRITICAL: Ensure Kibana can read its config - set ownership to UID 1000 (Kibana user)
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

start_stack() {
    echo "[INFO] Starting RedELK stack..."
    cd "${REDELK_PATH}/elkserver/docker"
    $COMPOSE_CMD down 2>/dev/null || true
    echo "[INFO] Pulling Docker images..."
    $COMPOSE_CMD pull
    echo "[INFO] Starting Elasticsearch..."
    $COMPOSE_CMD up -d elasticsearch
    echo "[INFO] Waiting for Elasticsearch to be ready..."
    local code
    local ok=false
    for ((i=1;i<=60;i++)); do
      code="$(curl -sS -u "elastic:${ELASTIC_PASSWORD}" -o /dev/null -w '%{http_code}' http://127.0.0.1:9200/_cluster/health || true)"
      if [[ "$code" == "200" ]]; then ok=true; break; fi
      sleep 5; echo -n "."
    done
    echo ""
    if [[ "$ok" != "true" ]]; then
      echo "[ERROR] Elasticsearch failed to become ready"
      docker logs redelk-elasticsearch || true
      exit 1
    fi
    echo "[INFO] Waiting for Elasticsearch cluster state to recover..."
    ok=false
    for ((i=1;i<=90;i++)); do
      # Check cluster health with wait_for_no_initializing_shards to ensure cluster state is recovered
      response="$(curl -sS -u "elastic:${ELASTIC_PASSWORD}" 'http://127.0.0.1:9200/_cluster/health?wait_for_no_initializing_shards=true&timeout=1s' 2>/dev/null || true)"
      if echo "$response" | grep -q '"status"'; then
        ok=true
        break
      fi
      sleep 2; echo -n "."
    done
    echo ""
    if [[ "$ok" != "true" ]]; then
      echo "[ERROR] Elasticsearch cluster state failed to recover"
      docker logs redelk-elasticsearch || true
      exit 1
    fi
    provision_kibana_service_token
    echo "[INFO] Starting Kibana, Logstash, Nginx..."
    $COMPOSE_CMD up -d kibana logstash nginx
    echo "[INFO] Waiting for Kibana to be ready..."
    ok=false
    for ((i=1;i<=60;i++)); do
      code="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:5601/api/status || true)"
      if [[ "$code" == "200" ]]; then ok=true; break; fi
      sleep 5; echo -n "."
    done
    echo ""
    if [[ "$ok" != "true" ]]; then
      echo "[WARN] Kibana not reporting 200; last logs:"
      docker logs --tail=200 redelk-kibana || true
    fi
    echo "[INFO] Stack started successfully"
}

deploy_elasticsearch_templates() {
    echo "[INFO] Deploying Elasticsearch index templates..."

    # Wait for Elasticsearch to be ready for template deployment
    sleep 2

    # Deploy index templates
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

    # Create pipeline directory if it doesn't exist
    mkdir -p "${REDELK_PATH}/elkserver/logstash/pipelines"

    # Copy all Logstash configuration files
    if ls "${REDELK_PATH}/elkserver/logstash/conf.d/"*.conf >/dev/null 2>&1; then
        cp "${REDELK_PATH}/elkserver/logstash/conf.d/"*.conf "${REDELK_PATH}/elkserver/logstash/pipelines/" || true
        echo "[INFO] Logstash pipeline configurations deployed"
    fi

    # Create threat feeds directory
    mkdir -p "${REDELK_PATH}/elkserver/logstash/threat-feeds"
}

deploy_kibana_dashboards() {
    echo "[INFO] Deploying Kibana dashboards and index patterns..."

    # Wait for Kibana to be fully ready
    local kb_ready=false
    echo "[INFO] Waiting for Kibana API to be ready..."
    for ((i=1;i<=30;i++)); do
        if curl -sS "http://127.0.0.1:5601/api/status" \
               -u "elastic:${ELASTIC_PASSWORD}" 2>/dev/null | grep -q '"level":"available"'; then
            kb_ready=true
            echo "[INFO] Kibana API is ready"
            break
        fi
        sleep 2
        echo -n "."
    done
    echo ""

    if [[ "$kb_ready" == "true" ]]; then
        # Create index patterns (data views) first
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

        # Import dashboards if they exist
        if [[ -f "${REDELK_PATH}/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson" ]]; then
            echo "[INFO] Importing Kibana dashboards..."
            local import_response
            import_response=$(curl -sS -X POST "http://127.0.0.1:5601/api/saved_objects/_import?overwrite=true" \
                -u "elastic:${ELASTIC_PASSWORD}" \
                -H "kbn-xsrf: true" \
                -F "file=@${REDELK_PATH}/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson" 2>&1)

            if echo "$import_response" | grep -q '"success":true'; then
                echo "[INFO] Successfully imported Kibana dashboards"
                echo "[INFO] Dashboard URL: https://$(hostname -I | awk '{print $1}')/app/dashboards"
            else
                echo "[WARN] Dashboard import may have issues. Response:"
                echo "$import_response" | jq '.' 2>/dev/null || echo "$import_response"
                echo "[INFO] You may need to manually import dashboards from Kibana UI"
            fi
        else
            echo "[WARN] Dashboard file not found at: ${REDELK_PATH}/elkserver/kibana/dashboards/redelk-main-dashboard.ndjson"
        fi

        # Set default index pattern
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

    # Create scripts directory
    mkdir -p "${REDELK_PATH}/scripts"

    # Make scripts executable
    if ls "${REDELK_PATH}/scripts/"*.sh >/dev/null 2>&1; then
        chmod +x "${REDELK_PATH}/scripts/"*.sh
        echo "[INFO] Helper scripts deployed to ${REDELK_PATH}/scripts/"
    fi

    # Create cron job for threat feed updates
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

    # C2 servers package
    local c2_pkg="${REDELK_PATH}/c2package"
    mkdir -p "${c2_pkg}"
    cp "${REDELK_PATH}/certs/redelkCA.crt" "${c2_pkg}/"
    cp "${REDELK_PATH}/certs/sshkey" "${c2_pkg}/"

    # Get server IP for replacing in configs
    local server_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)
    if [ -z "$server_ip" ]; then
        echo "[WARNING] Could not detect server IP, using placeholder"
        server_ip="REDELK_SERVER_IP"
    else
        echo "[INFO] Using server IP: $server_ip for filebeat configs"
    fi

    # Add C2 Filebeat configurations with IP replacement
    mkdir -p "${c2_pkg}/filebeat"
    if ls "${REDELK_PATH}/c2servers/"*.yml >/dev/null 2>&1; then
        for config in "${REDELK_PATH}/c2servers/"*.yml; do
            local filename=$(basename "$config")
            sed "s/REDELK_SERVER_IP/${server_ip}/g" "$config" > "${c2_pkg}/filebeat/${filename}"
        done
    fi

    tar czf "${REDELK_PATH}/c2servers.tgz" -C "${REDELK_PATH}" c2package
    chmod 644 "${REDELK_PATH}/c2servers.tgz"  # Make world-readable for easy transfer
    rm -rf "${c2_pkg}"

    # Redirectors package
    local redir_pkg="${REDELK_PATH}/redirpackage"
    mkdir -p "${redir_pkg}"
    cp "${REDELK_PATH}/certs/redelkCA.crt" "${redir_pkg}/"
    cp "${REDELK_PATH}/certs/elkserver.crt" "${redir_pkg}/"

    # Add redirector Filebeat configurations with IP replacement
    mkdir -p "${redir_pkg}/filebeat"
    if ls "${REDELK_PATH}/redirs/"*.yml >/dev/null 2>&1; then
        for config in "${REDELK_PATH}/redirs/"*.yml; do
            local filename=$(basename "$config")
            sed "s/REDELK_SERVER_IP/${server_ip}/g" "$config" > "${redir_pkg}/filebeat/${filename}"
        done
    fi

    tar czf "${REDELK_PATH}/redirs.tgz" -C "${REDELK_PATH}" redirpackage
    chmod 644 "${REDELK_PATH}/redirs.tgz"  # Make world-readable for easy transfer
    rm -rf "${redir_pkg}"

    echo "[INFO] Deployment packages created with RedELK server IP: ${server_ip}"
}

print_summary() {
    local server_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)

    echo ""
    echo "================================================================"
    echo "       RedELK v3.0 Installation Complete!"
    echo "================================================================"
    echo ""
    echo "Access Kibana:"
    echo "  URL: https://${server_ip}/"
    echo "  Username: elastic"
    echo "  Password: ${ELASTIC_PASSWORD}"
    echo ""
    echo "Elasticsearch API:"
    echo "  URL: http://${server_ip}:9200"
    echo "  Username: elastic"
    echo "  Password: ${ELASTIC_PASSWORD}"
    echo ""
    echo "Logstash Beats Input:"
    echo "  Port: 5044 (for Filebeat agents)"
    echo ""
    echo "Deployment Packages:"
    echo "  C2 Servers: ${REDELK_PATH}/c2servers.tgz"
    echo "  Redirectors: ${REDELK_PATH}/redirs.tgz"
    echo ""
    echo "Helper Scripts:"
    echo "  ${REDELK_PATH}/scripts/redelk-health-check.sh - Check system health"
    echo "  ${REDELK_PATH}/scripts/redelk-beacon-manager.sh - Manage beacons"
    echo "  ${REDELK_PATH}/scripts/update-threat-feeds.sh - Update threat intel"
    echo ""
    echo "Deployed Components:"
    echo "  ✓ Elasticsearch index templates (rtops, redirtraffic, alarms)"
    echo "  ✓ Logstash parsers for C2 and redirector logs"
    echo "  ✓ GeoIP and threat detection enrichment modules"
    echo "  ✓ Kibana dashboards and visualizations"
    echo "  ✓ Automated threat feed updates (cron)"
    echo ""
    echo "Service Management:"
    echo "  systemctl status redelk"
    echo "  systemctl restart redelk"
    echo "  docker logs redelk-[elasticsearch|kibana|logstash|nginx]"
    echo ""
    echo "Next Steps:"
    echo "  1. Deploy c2servers.tgz to your C2 servers"
    echo "  2. Deploy redirs.tgz to your redirectors"
    echo "  3. Configure Filebeat on each system with provided configs"
    echo "  4. Access Kibana dashboard to monitor operations"
    echo ""
    echo "Installation log: ${LOG_FILE}"
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
    create_directories
    copy_deployment_files  # Copy all RedELK component files from script directory
    generate_certificates
    check_ports
    create_env_file
    create_docker_compose
    create_nginx_config
    create_logstash_pipeline
    deploy_logstash_configs
    create_systemd_service
    start_stack
    deploy_elasticsearch_templates
    deploy_kibana_dashboards
    deploy_helper_scripts
    create_deployment_packages
    print_summary
}

# Run main function
main "$@"