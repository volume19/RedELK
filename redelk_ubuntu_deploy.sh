#!/usr/bin/env bash
# RedELK v3.0 - Production Deployment Script
# Fully idempotent, non-interactive deployment for Ubuntu 20.04/22.04/24.04

set -Eeuo pipefail
trap 'echo "Error at line $LINENO: $BASH_COMMAND" >&2' ERR

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/redelk_deploy.log"
readonly REDELK_PATH="/opt/RedELK"
readonly ELASTIC_PASSWORD="RedElk2024Secure"
readonly KIBANA_PASSWORD="KibanaRedElk2024"
readonly ES_JAVA_OPTS="-Xms2g -Xmx2g"

# Export for Docker Compose
export REDELK_PATH ELASTIC_PASSWORD KIBANA_PASSWORD ES_JAVA_OPTS

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

sanitize_script() {
    # Remove Windows line endings and BOM
    sed -i 's/\r$//' "$0" 2>/dev/null || true
    sed -i '1s/^\xEF\xBB\xBF//' "$0" 2>/dev/null || true
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
    mkdir -p "${REDELK_PATH}"/{elkserver/{docker,nginx,logstash/pipelines},certs,logs}

    # Set proper permissions for Elasticsearch
    mkdir -p "${REDELK_PATH}/elasticsearch-data"
    chown -R 1000:1000 "${REDELK_PATH}/elasticsearch-data"
}

generate_certificates() {
    echo "[INFO] Generating TLS certificates..."
    local cert_dir="${REDELK_PATH}/certs"
    cd "$cert_dir"

    # Skip if already generated
    if [[ -f elkserver.crt && -f redelkCA.crt && -f sshkey ]]; then
        echo "[INFO] Certificates already exist, skipping"
        return
    fi

    # Get server IP
    local server_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)

    # Create OpenSSL config
    cat > config.cnf <<EOF
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
    openssl genrsa -out redelkCA.key 4096 2>/dev/null
    openssl req -new -x509 -days 3650 -key redelkCA.key -out redelkCA.crt \
        -subj "/CN=RedELK CA" 2>/dev/null

    # Generate server certificate
    openssl genrsa -out elkserver.key 4096 2>/dev/null
    openssl req -new -key elkserver.key -out elkserver.csr -config config.cnf 2>/dev/null
    openssl x509 -req -in elkserver.csr -CA redelkCA.crt -CAkey redelkCA.key \
        -CAcreateserial -out elkserver.crt -days 3650 -extensions v3_req \
        -extfile config.cnf 2>/dev/null

    # Generate SSH keys
    rm -f sshkey sshkey.pub
    ssh-keygen -t ed25519 -f sshkey -N "" -q
}

check_ports() {
    echo "[INFO] Checking port availability..."
    local ports=(80 443 5601 5044 9200)
    local port_in_use=false

    for port in "${ports[@]}"; do
        if ss -ltn | grep -q ":$port "; then
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
KIBANA_PASSWORD=${KIBANA_PASSWORD}
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
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=false
      - xpack.security.authc.api_key.enabled=true
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - ES_JAVA_OPTS=${ES_JAVA_OPTS}
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
    ulimits:
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
    environment:
      - SERVERNAME=kibana
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=elastic
      - ELASTICSEARCH_PASSWORD=${ELASTIC_PASSWORD}
      - ELASTICSEARCH_SSL_VERIFICATIONMODE=none
      - SERVER_SSL_ENABLED=false
      - TELEMETRY_ENABLED=false
      - SERVER_PUBLICBASEURL=https://localhost
    ports:
      - "127.0.0.1:5601:5601"
    depends_on:
      elasticsearch:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:5601/api/status || exit 1"]
      interval: 10s
      timeout: 10s
      retries: 60
      start_period: 90s
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
        condition: service_healthy
    networks:
      - redelk

networks:
  redelk:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
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
    user => "elastic"
    password => "${ELASTIC_PASSWORD}"
    index => "%{[@metadata][index_prefix]}-%{+YYYY.MM.dd}"
    template_name => "redelk"
    template_overwrite => true
  }
}
EOF
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
ExecStart=${COMPOSE_CMD} up -d
ExecStop=${COMPOSE_CMD} down
ExecReload=${COMPOSE_CMD} restart
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

    # Stop any existing containers
    $COMPOSE_CMD down 2>/dev/null || true

    # Pull latest images
    echo "[INFO] Pulling Docker images..."
    $COMPOSE_CMD pull

    # Start services
    echo "[INFO] Starting services..."
    $COMPOSE_CMD up -d

    # Wait for Elasticsearch
    echo "[INFO] Waiting for Elasticsearch to be ready..."
    local attempts=0
    while ! curl -fsS -u elastic:${ELASTIC_PASSWORD} http://127.0.0.1:9200/_cluster/health >/dev/null 2>&1; do
        sleep 5
        ((attempts++))
        if [[ $attempts -gt 60 ]]; then
            echo "[ERROR] Elasticsearch failed to start"
            docker logs redelk-elasticsearch
            exit 1
        fi
        echo -n "."
    done
    echo ""

    # Wait for Kibana
    echo "[INFO] Waiting for Kibana to be ready..."
    attempts=0
    while ! curl -fsS http://127.0.0.1:5601/api/status >/dev/null 2>&1; do
        sleep 5
        ((attempts++))
        if [[ $attempts -gt 60 ]]; then
            echo "[ERROR] Kibana failed to start"
            docker logs redelk-kibana
            exit 1
        fi
        echo -n "."
    done
    echo ""

    echo "[INFO] Stack started successfully"
}

create_deployment_packages() {
    echo "[INFO] Creating deployment packages..."
    cd "${REDELK_PATH}"

    # C2 servers package
    mkdir -p c2package
    cp certs/redelkCA.crt c2package/
    cp certs/sshkey c2package/
    tar czf c2servers.tgz c2package
    rm -rf c2package

    # Redirectors package
    mkdir -p redirpackage
    cp certs/redelkCA.crt redirpackage/
    cp certs/elkserver.crt redirpackage/
    tar czf redirs.tgz redirpackage
    rm -rf redirpackage
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
    echo "Deployment Packages:"
    echo "  C2 Servers: ${REDELK_PATH}/c2servers.tgz"
    echo "  Redirectors: ${REDELK_PATH}/redirs.tgz"
    echo ""
    echo "Service Management:"
    echo "  systemctl status redelk"
    echo "  systemctl restart redelk"
    echo "  docker logs redelk-elasticsearch"
    echo ""
    echo "Installation log: ${LOG_FILE}"
    echo ""
}

main() {
    print_banner
    sanitize_script
    check_root
    print_facts
    check_ubuntu
    install_dependencies
    install_docker
    setup_kernel
    create_directories
    generate_certificates
    check_ports
    create_env_file
    create_docker_compose
    create_nginx_config
    create_logstash_pipeline
    create_systemd_service
    start_stack
    create_deployment_packages
    print_summary
}

# Run main function
main "$@"