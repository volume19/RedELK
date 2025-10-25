#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Error at line $LINENO: $BASH_COMMAND" >&2' ERR

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/redelk_deploy.log"
readonly REDELK_PATH="${REDELK_PATH:-/opt/RedELK}"
readonly COMPOSE_CMD="$(command -v docker-compose || echo "docker compose")"

exec > >(tee -a "$LOG_FILE")
exec 2>&1

sanitize_script() {
    sed -i 's/\r$//' "$0" 2>/dev/null || true
    sed -i '1s/^\xEF\xBB\xBF//' "$0" 2>/dev/null || true
}

check_root() {
    [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
}

print_facts() {
    echo "Host: $(hostname)"
    echo "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Docker: $(docker --version 2>/dev/null || echo "Not installed")"
    echo "Compose: $COMPOSE_CMD"
    echo "REDELK_PATH: $REDELK_PATH"
    echo "Timestamp: $(date -Iseconds)"
}

setup_env() {
    if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
        cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
    fi
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
    export REDELK_PATH="${REDELK_PATH}"
    export ELASTIC_PASSWORD="${ELASTIC_PASSWORD}"
    export ES_JAVA_OPTS="${ES_JAVA_OPTS}"
}

create_directories() {
    mkdir -p "${REDELK_PATH}"/{elkserver/{docker,nginx,logstash/pipelines},certs,logs}
    chown -R 1000:1000 "${REDELK_PATH}"
}

generate_certs() {
    local cert_dir="${REDELK_PATH}/certs"
    cd "$cert_dir"

    if [[ -f elkserver.crt && -f redelkCA.crt && -f sshkey ]]; then
        return 0
    fi

    local server_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)

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
IP.1 = 127.0.0.1
IP.2 = ${server_ip}
EOF

    openssl genrsa -out redelkCA.key 4096 2>/dev/null
    openssl req -new -x509 -days 3650 -key redelkCA.key -out redelkCA.crt -subj "/CN=RedELK CA" 2>/dev/null
    openssl genrsa -out elkserver.key 4096 2>/dev/null
    openssl req -new -key elkserver.key -out elkserver.csr -config config.cnf 2>/dev/null
    openssl x509 -req -in elkserver.csr -CA redelkCA.crt -CAkey redelkCA.key -CAcreateserial -out elkserver.crt -days 3650 -extensions v3_req -extfile config.cnf 2>/dev/null

    rm -f sshkey sshkey.pub
    ssh-keygen -t ed25519 -f sshkey -N "" -q
}

setup_kernel() {
    sysctl -w vm.max_map_count=262144 >/dev/null 2>&1
    cp "${SCRIPT_DIR}/linux/99-elastic.conf" /etc/sysctl.d/
    sysctl --system >/dev/null 2>&1
}

check_ports() {
    local ports=(80 443 5601 5044 9200)
    for port in "${ports[@]}"; do
        if ss -ltn | grep -q ":$port "; then
            echo "Port $port in use. Run: ss -ltnp | grep :$port"
            exit 1
        fi
    done
}

create_compose() {
    cat > "${REDELK_PATH}/elkserver/docker/docker-compose.yml" <<'EOF'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.3
    container_name: redelk-elasticsearch
    restart: unless-stopped
    environment:
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=false
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - ES_JAVA_OPTS=${ES_JAVA_OPTS}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - es_data:/usr/share/elasticsearch/data
      - ${REDELK_PATH}/certs:/usr/share/elasticsearch/config/certs:ro
    ports:
      - "127.0.0.1:9200:9200"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=1s | grep -q status"]
      interval: 10s
      timeout: 5s
      retries: 30
    networks:
      - redelk

  logstash:
    image: docker.elastic.co/logstash/logstash:8.11.3
    container_name: redelk-logstash
    restart: unless-stopped
    environment:
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - xpack.monitoring.enabled=false
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
    image: docker.elastic.co/kibana/kibana:8.11.3
    container_name: redelk-kibana
    restart: unless-stopped
    environment:
      - SERVERNAME=kibana
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=elastic
      - ELASTICSEARCH_PASSWORD=${ELASTIC_PASSWORD}
      - SERVER_SSL_ENABLED=false
    ports:
      - "127.0.0.1:5601:5601"
    depends_on:
      elasticsearch:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:5601/api/status | grep -q available"]
      interval: 10s
      timeout: 5s
      retries: 30
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

volumes:
  es_data:
    driver: local
EOF
}

create_nginx_conf() {
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
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;
        ssl_certificate /etc/nginx/certs/elkserver.crt;
        ssl_certificate_key /etc/nginx/certs/elkserver.key;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass http://kibana;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF
}

create_logstash_pipeline() {
    cat > "${REDELK_PATH}/elkserver/logstash/pipelines/main.conf" <<'EOF'
input {
  beats {
    port => 5044
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
  }
}
EOF
}

create_systemd_service() {
    cat > /etc/systemd/system/redelk-compose.service <<EOF
[Unit]
Description=RedELK Stack
After=docker.service
Requires=docker.service

[Service]
Type=forking
WorkingDirectory=${REDELK_PATH}/elkserver/docker
Environment="REDELK_PATH=${REDELK_PATH}"
ExecStartPre=/bin/bash -c 'source ${SCRIPT_DIR}/.env && export REDELK_PATH ELASTIC_PASSWORD ES_JAVA_OPTS'
ExecStart=/bin/bash -c 'source ${SCRIPT_DIR}/.env && ${COMPOSE_CMD} up -d'
ExecStop=${COMPOSE_CMD} down
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

start_stack() {
    cd "${REDELK_PATH}/elkserver/docker"
    cp "${SCRIPT_DIR}/.env" .

    $COMPOSE_CMD down -v 2>/dev/null || true
    $COMPOSE_CMD up -d

    echo "Waiting for Elasticsearch..."
    local attempts=0
    while ! curl -fsS -u elastic:${ELASTIC_PASSWORD} http://127.0.0.1:9200/_cluster/health >/dev/null 2>&1; do
        sleep 5
        ((attempts++))
        if [[ $attempts -gt 60 ]]; then
            echo "Elasticsearch failed to start"
            exit 1
        fi
    done

    echo "Waiting for Kibana..."
    attempts=0
    while ! curl -fsS http://127.0.0.1:5601/api/status >/dev/null 2>&1; do
        sleep 5
        ((attempts++))
        if [[ $attempts -gt 60 ]]; then
            echo "Kibana failed to start"
            exit 1
        fi
    done
}

main() {
    sanitize_script
    check_root
    print_facts
    setup_env
    create_directories
    generate_certs
    setup_kernel
    check_ports
    create_compose
    create_nginx_conf
    create_logstash_pipeline
    create_systemd_service
    start_stack
    echo "Deployment complete"
}

main "$@"