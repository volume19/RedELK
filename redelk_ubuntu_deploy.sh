#!/bin/bash
#
# RedELK v3.0 - Ubuntu Server Deployment Script
# Deploys complete RedELK stack on fresh Ubuntu 20.04/22.04/24.04
# Run with: bash redelk_ubuntu_deploy.sh
#
# Simple error handling for maximum compatibility
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REDELK_VERSION="3.0"
REDELK_PATH="/opt/RedELK"
DOCKER_COMPOSE_VERSION="2.34.0"
ELK_VERSION="8.11.3"

# Banner
print_banner() {
    echo ""
    echo "    ____            _  _____  _      _  __"
    echo "   |  _ \  ___   __| || ____|| |    | |/ /"
    echo "   | |_) |/ _ \ / _  ||  _|  | |    | ' / "
    echo "   |  _ <|  __/| (_| || |___ | |___ | . \ "
    echo "   |_| \__\___| \____||_____||_____||_|\_\\"
    echo ""
    echo "   Ubuntu Server Deployment v${REDELK_VERSION}"
    echo ""
}

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1"
    exit 1
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Check Ubuntu version
check_ubuntu() {
    if ! command -v lsb_release > /dev/null 2>&1; then
        error "This script requires Ubuntu 20.04/22.04/24.04"
    fi

    VERSION=$(lsb_release -rs)
    case "$VERSION" in
        20.04|22.04|24.04)
            log "Ubuntu $VERSION detected"
            ;;
        *)
            error "Unsupported Ubuntu version: $VERSION. Requires 20.04/22.04/24.04"
            ;;
    esac
}

# Update system
update_system() {
    log "Updating system packages..."
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y \
        curl \
        wget \
        git \
        openssl \
        ca-certificates \
        gnupg \
        lsb-release \
        net-tools \
        htop \
        vim \
        jq \
        unzip
}

# Install Docker
install_docker() {
    if command -v docker > /dev/null 2>&1; then
        log "Docker already installed"
        return
    fi

    log "Installing Docker..."

    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Set up repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

    # Start and enable Docker
    systemctl start docker
    systemctl enable docker

    log "Docker installed successfully "
}

# Install Docker Compose
install_docker_compose() {
    if command -v docker-compose > /dev/null 2>&1; then
        log "Docker Compose already installed"
        return
    fi

    log "Installing Docker Compose v${DOCKER_COMPOSE_VERSION}..."

    # Install Docker Compose v2
    apt-get install -y docker-compose-plugin

    # Create symlink for backwards compatibility
    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

    log "Docker Compose installed successfully "
}

# Create RedELK directory structure
create_directories() {
    log "Creating RedELK directory structure..."

    mkdir -p ${REDELK_PATH}/{elkserver,c2servers,redirs,certs,scripts,logs}
    mkdir -p ${REDELK_PATH}/elkserver/{docker,config,logstash,kibana,elasticsearch,nginx,neo4j}
    mkdir -p ${REDELK_PATH}/elkserver/logstash/{pipelines,ruby-scripts}

    log "Directory structure created "
}

# Generate certificates
generate_certificates() {
    log "Generating TLS certificates..."

    cd ${REDELK_PATH}/certs

    # Get server IP
    SERVER_IP=$(ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)

    # Create OpenSSL config
    cat > config.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = RedELK
OU = Security
CN = redelk.local

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = redelk.local
DNS.3 = *.redelk.local
IP.1 = 127.0.0.1
IP.2 = ${SERVER_IP}
EOF

    # Generate CA
    openssl genrsa -out redelkCA.key 4096
    openssl req -new -x509 -days 3650 -key redelkCA.key -out redelkCA.crt \
        -subj "/C=US/ST=State/L=City/O=RedELK/CN=RedELK CA"

    # Generate server certificate
    openssl genrsa -out elkserver.key 4096
    openssl req -new -key elkserver.key -out elkserver.csr -config config.cnf
    openssl x509 -req -in elkserver.csr -CA redelkCA.crt -CAkey redelkCA.key \
        -CAcreateserial -out elkserver.crt -days 3650 -extensions v3_req \
        -extfile config.cnf

    # Generate SSH keys
    ssh-keygen -t ed25519 -f sshkey -N "" -C "redelk@${HOSTNAME}"

    log "Certificates generated "
}

# Download RedELK files
download_redelk() {
    log "Downloading RedELK configuration files..."

    cd ${REDELK_PATH}

    # Clone repository or download release
    if [ -d ".git" ]; then
        git pull
    else
        git clone https://github.com/outflanknl/RedELK.git /tmp/redelk
        cp -r /tmp/redelk/* ${REDELK_PATH}/ 2>/dev/null || true
    fi

    log "RedELK files downloaded "
}

# Create Docker Compose configuration
create_docker_compose() {
    log "Creating Docker Compose configuration..."

    cat > ${REDELK_PATH}/elkserver/docker/docker-compose.yml <<'EOF'
version: '3.8'

networks:
  redelk:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.3
    container_name: redelk-elasticsearch
    restart: always
    networks:
      redelk:
        ipv4_address: 172.28.0.2
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - xpack.security.authc.api_key.enabled=true
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD:-RedElk2024Secure!}
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - esdata:/usr/share/elasticsearch/data
      - ${REDELK_PATH}/certs:/usr/share/elasticsearch/config/certs:ro
    ports:
      - "127.0.0.1:9200:9200"
    healthcheck:
      test: ["CMD-SHELL", "curl -s -k https://localhost:9200/_cluster/health -u elastic:${ELASTIC_PASSWORD:-RedElk2024Secure!} | grep -q '\"status\":\"[green|yellow]\"'"]
      interval: 30s
      timeout: 10s
      retries: 5

  logstash:
    image: docker.elastic.co/logstash/logstash:8.11.3
    container_name: redelk-logstash
    restart: always
    networks:
      redelk:
        ipv4_address: 172.28.0.3
    environment:
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD:-RedElk2024Secure!}
      - xpack.monitoring.enabled=false
      - "LS_JAVA_OPTS=-Xmx1g -Xms1g"
    volumes:
      - ${REDELK_PATH}/elkserver/logstash/pipelines:/usr/share/logstash/pipeline:ro
      - ${REDELK_PATH}/elkserver/logstash/ruby-scripts:/usr/share/logstash/ruby-scripts:ro
      - ${REDELK_PATH}/certs:/usr/share/logstash/config/certs:ro
    ports:
      - "0.0.0.0:5044:5044"
    depends_on:
      elasticsearch:
        condition: service_healthy

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.3
    container_name: redelk-kibana
    restart: always
    networks:
      redelk:
        ipv4_address: 172.28.0.4
    environment:
      - SERVERNAME=kibana
      - ELASTICSEARCH_HOSTS=https://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${KIBANA_PASSWORD:-KibanaRedElk2024!}
      - ELASTICSEARCH_SSL_VERIFICATIONMODE=none
      - SERVER_SSL_ENABLED=true
      - SERVER_SSL_CERTIFICATE=/usr/share/kibana/config/certs/elkserver.crt
      - SERVER_SSL_KEY=/usr/share/kibana/config/certs/elkserver.key
    volumes:
      - ${REDELK_PATH}/certs:/usr/share/kibana/config/certs:ro
    ports:
      - "127.0.0.1:5601:5601"
    depends_on:
      elasticsearch:
        condition: service_healthy

  nginx:
    image: nginx:alpine
    container_name: redelk-nginx
    restart: always
    networks:
      redelk:
        ipv4_address: 172.28.0.5
    volumes:
      - ${REDELK_PATH}/elkserver/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ${REDELK_PATH}/certs:/etc/nginx/certs:ro
    ports:
      - "443:443"
      - "80:80"
    depends_on:
      - kibana

volumes:
  esdata:
    driver: local
EOF

    # Create .env file
    cat > ${REDELK_PATH}/elkserver/docker/.env <<EOF
# RedELK Environment Configuration
ELASTIC_PASSWORD=RedElk2024Secure!
KIBANA_PASSWORD=KibanaRedElk2024!
LOGSTASH_PASSWORD=LogstashRedElk2024!
COMPOSE_PROJECT_NAME=redelk
EOF

    log "Docker Compose configuration created "
}

# Create Nginx configuration
create_nginx_config() {
    log "Creating Nginx configuration..."

    cat > ${REDELK_PATH}/elkserver/nginx/nginx.conf <<'EOF'
events {
    worker_connections 1024;
}

http {
    upstream kibana {
        server kibana:5601;
    }

    server {
        listen 80;
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name _;

        ssl_certificate /etc/nginx/certs/elkserver.crt;
        ssl_certificate_key /etc/nginx/certs/elkserver.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        location / {
            proxy_pass https://kibana;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_ssl_verify off;
        }
    }
}
EOF

    log "Nginx configuration created "
}

# Create basic Logstash pipeline
create_logstash_pipeline() {
    log "Creating Logstash pipeline..."

    cat > ${REDELK_PATH}/elkserver/logstash/pipelines/main.conf <<'EOF'
input {
  beats {
    port => 5044
    ssl => true
    ssl_certificate => "/usr/share/logstash/config/certs/elkserver.crt"
    ssl_key => "/usr/share/logstash/config/certs/elkserver.key"
    ssl_verify_mode => "force_peer"
    ssl_certificate_authorities => ["/usr/share/logstash/config/certs/redelkCA.crt"]
  }
}

filter {
  # Add your filter logic here
  mutate {
    add_field => { "[@metadata][index_prefix]" => "redelk" }
  }

  # Parse timestamps
  date {
    match => [ "timestamp", "ISO8601", "yyyy-MM-dd HH:mm:ss" ]
    target => "@timestamp"
  }
}

output {
  elasticsearch {
    hosts => ["https://elasticsearch:9200"]
    user => "elastic"
    password => "${ELASTIC_PASSWORD}"
    ssl => true
    ssl_certificate_verification => false
    index => "%{[@metadata][index_prefix]}-%{+YYYY.MM.dd}"
  }

  # Debug output (comment out in production)
  stdout { codec => rubydebug }
}
EOF

    log "Logstash pipeline created "
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service..."

    cat > /etc/systemd/system/redelk.service <<EOF
[Unit]
Description=RedELK SIEM Stack
Requires=docker.service
After=docker.service

[Service]
Type=forking
Restart=always
WorkingDirectory=${REDELK_PATH}/elkserver/docker
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable redelk

    log "Systemd service created "
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."

    # Enable UFW if not already
    if ! command -v ufw > /dev/null 2>&1; then
        apt-get install -y ufw
    fi

    # Configure firewall rules
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH
    ufw allow 22/tcp comment "SSH"

    # Allow RedELK services
    ufw allow 443/tcp comment "RedELK Kibana HTTPS"
    ufw allow 5044/tcp comment "RedELK Logstash Beats"

    # Allow Docker networks
    ufw allow in on docker0

    ufw reload

    log "Firewall configured "
}

# Start services
start_services() {
    log "Starting RedELK services..."

    cd ${REDELK_PATH}/elkserver/docker

    # Pull images
    docker-compose pull

    # Start services
    docker-compose up -d

    # Wait for services to be healthy
    log "Waiting for services to be healthy..."
    sleep 30

    # Check service status
    docker-compose ps

    log "Services started "
}

# Setup Elasticsearch passwords
setup_passwords() {
    log "Setting up Elasticsearch passwords..."

    # Wait for Elasticsearch to be fully ready
    sleep 20

    # Set kibana_system password
    echo "KibanaRedElk2024!" | docker exec -i redelk-elasticsearch elasticsearch-reset-password -u kibana_system -b -i

    # Create redelk user
    docker exec redelk-elasticsearch elasticsearch-users useradd redelk -p redelk -r superuser 2>/dev/null || true

    log "Passwords configured "
}

# Create package for remote deployments
create_deployment_packages() {
    log "Creating deployment packages..."

    cd ${REDELK_PATH}

    # C2 Server package
    tar czf c2servers.tgz \
        certs/redelkCA.crt \
        certs/sshkey \
        scripts/getremotelogs.sh \
        c2servers/filebeat.yml

    # Redirector package
    tar czf redirs.tgz \
        certs/redelkCA.crt \
        certs/elkserver.crt \
        redirs/filebeat.yml

    log "Deployment packages created "
}

# Print summary
print_summary() {
    SERVER_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)

    echo ""
    echo "================================================================"
    echo "       RedELK v${REDELK_VERSION} Installation Complete!"
    echo "================================================================"
    echo ""
    echo "Access Kibana:"
    echo "  URL: https://${SERVER_IP}/"
    echo "  Username: redelk"
    echo "  Password: redelk"
    echo ""
    echo "Elasticsearch:"
    echo "  URL: https://${SERVER_IP}:9200"
    echo "  Username: elastic"
    echo "  Password: RedElk2024Secure!"
    echo ""
    echo "Deployment Packages:"
    echo "  C2 Servers: ${REDELK_PATH}/c2servers.tgz"
    echo "  Redirectors: ${REDELK_PATH}/redirs.tgz"
    echo ""
    echo "Service Management:"
    echo "  Start: systemctl start redelk"
    echo "  Stop: systemctl stop redelk"
    echo "  Status: systemctl status redelk"
    echo "  Logs: docker-compose -f ${REDELK_PATH}/elkserver/docker/docker-compose.yml logs"
    echo ""
    echo "Next Steps:"
    echo "  1. Change default passwords immediately"
    echo "  2. Deploy Filebeat on C2 servers using c2servers.tgz"
    echo "  3. Deploy Filebeat on redirectors using redirs.tgz"
    echo "  4. Import Kibana dashboards"
    echo ""
    echo "Installation log: ${REDELK_PATH}/logs/install.log"
    echo ""
}

# Main execution
main() {
    print_banner

    # Create log file
    mkdir -p ${REDELK_PATH}/logs
    exec > >(tee -a ${REDELK_PATH}/logs/install.log)
    exec 2>&1

    log "Starting RedELK installation on $(hostname)..."

    check_root
    check_ubuntu
    update_system
    install_docker
    install_docker_compose
    create_directories
    generate_certificates
    download_redelk
    create_docker_compose
    create_nginx_config
    create_logstash_pipeline
    create_systemd_service
    configure_firewall
    start_services
    setup_passwords
    create_deployment_packages

    print_summary

    log "Installation completed successfully!"
}

# Run main function
main "$@"