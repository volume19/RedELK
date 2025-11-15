#!/usr/bin/env bash
set -Eeuo pipefail

trap 'on_error $LINENO "$BASH_COMMAND"' ERR

on_error() {
    local line="$1"
    local cmd="$2"
    printf '[ERROR] Command failed at line %s: %s\n' "$line" "$cmd" >&2
}

normalize_self() {
    local target="$1"
    local modified=false
    if LC_ALL=C grep -q $'\r' "$target"; then
        local tmp
        tmp=$(mktemp)
        tr -d '\r' <"$target" >"$tmp"
        cat "$tmp" >"$target"
        rm -f "$tmp"
        modified=true
    fi
    local bom
    bom=$(head -c 3 "$target" | od -An -t x1 | tr -d ' \n')
    if [[ "$bom" == "efbbbf" ]]; then
        local tmp
        tmp=$(mktemp)
        tail -c +4 "$target" >"$tmp"
        cat "$tmp" >"$target"
        rm -f "$tmp"
        modified=true
    fi
    if [[ "$modified" == true ]]; then
        printf '[INFO] Normalized line endings for %s\n' "$target"
    fi
}

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
normalize_self "$SCRIPT_PATH"

umask 077

readonly START_PWD="$(pwd)"
readonly REDELK_VERSION="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo 'unknown')"
readonly REDELK_PATH="${REDELK_PATH:-/opt/RedELK}"
readonly ELASTIC_VERSION="${ELASTIC_VERSION:-8.15.3}"
readonly ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-RedElk2024Secure}"
readonly ES_JAVA_OPTS="${ES_JAVA_OPTS:--Xms2g -Xmx2g}"
readonly LS_JAVA_OPTS="${LS_JAVA_OPTS:--Xms1g -Xmx1g}"
readonly LOG_FILE="/var/log/redelk_deploy.log"
readonly RUN_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

readonly SOURCE_ROOT="${SCRIPT_DIR}"
readonly SOURCE_LOGSTASH_CONF_DIR="${SOURCE_ROOT}/elkserver/logstash/conf.d"
readonly SOURCE_TEMPLATE_DIR="${SOURCE_ROOT}/elkserver/elasticsearch/index-templates"
readonly SOURCE_THREAT_FEED_DIR="${SOURCE_ROOT}/elkserver/logstash/threat-feeds"
readonly SOURCE_DASHBOARD_DIR="${SOURCE_ROOT}/elkserver/kibana/dashboards"
readonly SOURCE_HELPER_SCRIPT_DIR="${SOURCE_ROOT}/scripts"
readonly SOURCE_C2_DIR="${SOURCE_ROOT}/c2servers"
readonly SOURCE_REDIR_DIR="${SOURCE_ROOT}/redirs"

readonly ELK_ROOT="${REDELK_PATH}/elkserver"
readonly CONF_DEST_DIR="${ELK_ROOT}/logstash/conf.d"
readonly PIPELINE_DIR="${ELK_ROOT}/logstash/pipelines"
readonly PIPELINE_CONFIG="${ELK_ROOT}/logstash/pipelines.yml"
readonly TEMPLATE_DEST_DIR="${ELK_ROOT}/elasticsearch/index-templates"
readonly DASHBOARD_DEST_DIR="${ELK_ROOT}/kibana/dashboards"
readonly THREAT_FEED_DEST_DIR="${ELK_ROOT}/logstash/threat-feeds"
readonly HELPER_SCRIPT_DEST_DIR="${REDELK_PATH}/scripts"
readonly C2_DEST_DIR="${REDELK_PATH}/c2servers"
readonly REDIR_DEST_DIR="${REDELK_PATH}/redirs"
readonly CONFIG_DIR="${ELK_ROOT}/config"
readonly CERT_DIR="${REDELK_PATH}/certs"
readonly NGINX_DIR="${ELK_ROOT}/nginx"
readonly LOG_DIR_ROOT="${ELK_ROOT}/logs"
readonly ELASTIC_LOG_DIR="${LOG_DIR_ROOT}/elasticsearch"
readonly LOGSTASH_LOG_DIR="${LOG_DIR_ROOT}/logstash"
readonly KIBANA_LOG_DIR="${LOG_DIR_ROOT}/kibana"
readonly NGINX_LOG_DIR="${LOG_DIR_ROOT}/nginx"

LOGSTASH_CONF_FILES=()
TEMPLATE_FILES=()
THREAT_FEED_FILES=()
HELPER_SCRIPT_FILES=()
C2_CONFIG_FILES=()
REDIR_CONFIG_FILES=()
DASHBOARD_FILES=()

COMPOSE_CMD=()

log_info() {
    printf '[INFO] %s\n' "$*"
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

fatal() {
    log_error "$*"
    exit 1
}

ensure_directory() {
    local description="$1"
    local path="$2"
    if [[ ! -d "$path" ]]; then
        fatal "${description} directory not found: ${path}"
    fi
}

collect_files() {
    local directory="$1"
    local pattern="$2"
    find "$directory" -maxdepth 1 -type f -name "$pattern" -printf '%f\n' | sort
}

require_nonempty() {
    local description="$1"
    shift
    local -a files=("$@")
    if (( ${#files[@]} == 0 )); then
        fatal "No ${description} found in bundle"
    fi
}

load_source_manifests() {
    print_section "Inspecting Bundle Contents"

    ensure_directory "Logstash configuration" "$SOURCE_LOGSTASH_CONF_DIR"
    mapfile -t LOGSTASH_CONF_FILES < <(collect_files "$SOURCE_LOGSTASH_CONF_DIR" '*.conf')
    require_nonempty "Logstash pipeline configs" "${LOGSTASH_CONF_FILES[@]}"

    ensure_directory "Elasticsearch index templates" "$SOURCE_TEMPLATE_DIR"
    mapfile -t TEMPLATE_FILES < <(collect_files "$SOURCE_TEMPLATE_DIR" '*.json')
    require_nonempty "Elasticsearch index templates" "${TEMPLATE_FILES[@]}"

    ensure_directory "Threat feed" "$SOURCE_THREAT_FEED_DIR"
    mapfile -t THREAT_FEED_FILES < <(collect_files "$SOURCE_THREAT_FEED_DIR" '*.txt')
    require_nonempty "threat feed files" "${THREAT_FEED_FILES[@]}"

    ensure_directory "Helper script" "$SOURCE_HELPER_SCRIPT_DIR"
    mapfile -t HELPER_SCRIPT_FILES < <(collect_files "$SOURCE_HELPER_SCRIPT_DIR" '*.sh')
    require_nonempty "helper scripts" "${HELPER_SCRIPT_FILES[@]}"

    ensure_directory "C2 Filebeat configuration" "$SOURCE_C2_DIR"
    mapfile -t C2_CONFIG_FILES < <(collect_files "$SOURCE_C2_DIR" '*.yml')
    require_nonempty "C2 Filebeat configs" "${C2_CONFIG_FILES[@]}"

    ensure_directory "Redirector Filebeat configuration" "$SOURCE_REDIR_DIR"
    mapfile -t REDIR_CONFIG_FILES < <(collect_files "$SOURCE_REDIR_DIR" '*.yml')
    require_nonempty "redirector Filebeat configs" "${REDIR_CONFIG_FILES[@]}"

    ensure_directory "Kibana dashboards" "$SOURCE_DASHBOARD_DIR"
    mapfile -t DASHBOARD_FILES < <(collect_files "$SOURCE_DASHBOARD_DIR" '*.ndjson')
    require_nonempty "Kibana dashboards" "${DASHBOARD_FILES[@]}"

    log_info "Logstash configs: ${#LOGSTASH_CONF_FILES[@]}"
    log_info "Elasticsearch templates: ${#TEMPLATE_FILES[@]}"
    log_info "Threat feed files: ${#THREAT_FEED_FILES[@]}"
    log_info "Helper scripts: ${#HELPER_SCRIPT_FILES[@]}"
    log_info "C2 Filebeat configs: ${#C2_CONFIG_FILES[@]}"
    log_info "Redirector Filebeat configs: ${#REDIR_CONFIG_FILES[@]}"
    log_info "Kibana dashboards: ${#DASHBOARD_FILES[@]}"
}

print_section() {
    local title="$1"
    printf '\n============================================================\n'
    printf '== %s ==\n' "$title"
    printf '============================================================\n'
}

setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    log_info "Logging to $LOG_FILE"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        fatal "This script must be run as root"
    fi
}

detect_os() {
    print_section "Detecting Operating System"
    if [[ ! -r /etc/os-release ]]; then
        fatal "/etc/os-release not found; unsupported distribution"
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    log_info "Detected OS: ${NAME:-unknown} (${VERSION_ID:-unknown})"
    if [[ "${ID:-}" != "ubuntu" ]]; then
        fatal "Unsupported distribution: ${ID:-unknown}. Ubuntu 20.04/22.04/24.04 required."
    fi
    case "${VERSION_ID:-}" in
        20.04|22.04|24.04) ;;
        *) fatal "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Supported: 20.04 / 22.04 / 24.04." ;;
    esac
}

install_dependencies() {
    print_section "Installing Base Packages"
    log_info "Updating apt package index"
    apt-get update
    local packages=(
        apt-transport-https
        ca-certificates
        curl
        gnupg
        iproute2
        jq
        lsb-release
        netcat-openbsd
        openssl
        python3
        tar
        unzip
    )
    log_info "Installing packages: ${packages[*]}"
    apt-get install -y "${packages[@]}"
}

detect_compose_command() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD=(docker-compose)
    else
        fatal "docker compose plugin not available"
    fi
}

ensure_docker() {
    print_section "Ensuring Docker Engine"
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker not found; installing docker.io"
        apt-get install -y docker.io
    fi
    if ! systemctl is-enabled docker >/dev/null 2>&1; then
        log_info "Enabling docker service"
        systemctl enable docker
    fi
    if ! systemctl is-active --quiet docker; then
        log_info "Starting docker service"
        systemctl start docker
    fi
    if ! docker info >/dev/null 2>&1; then
        fatal "Docker daemon is not accessible"
    fi
    if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        log_info "Installing docker compose plugin"
        apt-get install -y docker-compose-plugin
    fi
    detect_compose_command
    log_info "Using compose command: ${COMPOSE_CMD[*]}"
    log_info "Docker server version: $(docker version --format '{{.Server.Version}}')"
}

preflight_checks() {
    print_section "Pre-Flight Verification"
    log_info "pwd: ${START_PWD}"
    log_info "SCRIPT_DIR: ${SCRIPT_DIR}"
    log_info "Listing bundle directory contents (first 20 items):"
    (cd "$SCRIPT_DIR" && ls -1 | head -n 20)

    local tools=(tar curl docker awk sed jq)
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            fatal "Required tool '$tool' not found in PATH"
        fi
        log_info "Tool available: $tool -> $(command -v "$tool")"
    done
    log_info "Bundle includes ${#LOGSTASH_CONF_FILES[@]} Logstash pipelines"
    log_info "Bundle includes ${#TEMPLATE_FILES[@]} Elasticsearch templates"
    log_info "Bundle includes ${#THREAT_FEED_FILES[@]} threat feed files"
    log_info "Bundle includes ${#HELPER_SCRIPT_FILES[@]} helper scripts"
    log_info "Bundle includes ${#C2_CONFIG_FILES[@]} C2 Filebeat configs"
    log_info "Bundle includes ${#REDIR_CONFIG_FILES[@]} redirector Filebeat configs"
    log_info "Bundle includes ${#DASHBOARD_FILES[@]} Kibana dashboards"
}

prepare_directories() {
    print_section "Preparing Target Directories"
    local dirs=(
        "$REDELK_PATH"
        "$ELK_ROOT"
        "$CONF_DEST_DIR"
        "$PIPELINE_DIR"
        "$TEMPLATE_DEST_DIR"
        "$DASHBOARD_DEST_DIR"
        "$THREAT_FEED_DEST_DIR"
        "$HELPER_SCRIPT_DEST_DIR"
        "$C2_DEST_DIR"
        "$REDIR_DEST_DIR"
        "$CONFIG_DIR"
        "$CERT_DIR"
        "$NGINX_DIR"
        "$LOG_DIR_ROOT"
        "$ELASTIC_LOG_DIR"
        "$LOGSTASH_LOG_DIR"
        "$KIBANA_LOG_DIR"
        "$NGINX_LOG_DIR"
    )
    for dir in "${dirs[@]}"; do
        log_info "Ensuring directory ${dir}"
        mkdir -p "$dir"
    done
}

copy_category() {
    local label="$1"
    local src_dir="$2"
    local dest_dir="$3"
    local mode="$4"
    shift 4
    local files=("$@")
    log_info "Deploying ${label} to ${dest_dir}"
    mkdir -p "$dest_dir"
    local copied=0
    for name in "${files[@]}"; do
        local src="${src_dir}/${name}"
        local dest="${dest_dir}/${name}"
        if [[ ! -f "$src" ]]; then
            fatal "Missing source file ${src} for ${label}"
        fi
        printf '[INFO] Copy %s -> %s\n' "$src" "$dest"
        install -m "$mode" "$src" "$dest"
        ((copied++))
    done
    local verified=0
    for name in "${files[@]}"; do
        if [[ -f "${dest_dir}/${name}" ]]; then
            ((verified++))
        fi
    done
    log_info "${label}: deployed ${verified} file(s)"
    if (( verified != copied )); then
        fatal "Deployment mismatch for ${label}: copied ${copied}, verified ${verified}"
    fi
}

copy_dashboards() {
    log_info "Deploying Kibana dashboards"
    mkdir -p "$DASHBOARD_DEST_DIR"
    local copied=0
    for name in "${DASHBOARD_FILES[@]}"; do
        local src="${SOURCE_DASHBOARD_DIR}/${name}"
        local dest="${DASHBOARD_DEST_DIR}/${name}"
        local size
        size=$(stat -c '%s' "$src")
        printf '[INFO] Copy %s -> %s (%s bytes)\n' "$src" "$dest" "$size"
        install -m 0644 "$src" "$dest"
        ((copied++))
    done
    if (( copied == 0 )); then
        fatal "No Kibana dashboards copied"
    fi
    log_info "Deployed ${copied} Kibana dashboard file(s)"
}

copy_deployment_files() {
    print_section "Copying Bundle Artifacts"
    copy_category "Logstash pipeline configs" "$SOURCE_LOGSTASH_CONF_DIR" "$CONF_DEST_DIR" 0644 "${LOGSTASH_CONF_FILES[@]}"
    copy_category "Elasticsearch index templates" "$SOURCE_TEMPLATE_DIR" "$TEMPLATE_DEST_DIR" 0644 "${TEMPLATE_FILES[@]}"
    copy_category "Threat feeds" "$SOURCE_THREAT_FEED_DIR" "$THREAT_FEED_DEST_DIR" 0644 "${THREAT_FEED_FILES[@]}"
    copy_category "Helper scripts" "$SOURCE_HELPER_SCRIPT_DIR" "$HELPER_SCRIPT_DEST_DIR" 0755 "${HELPER_SCRIPT_FILES[@]}"
    copy_category "C2 Filebeat configurations" "$SOURCE_C2_DIR" "$C2_DEST_DIR" 0644 "${C2_CONFIG_FILES[@]}"
    copy_category "Redirector Filebeat configurations" "$SOURCE_REDIR_DIR" "$REDIR_DEST_DIR" 0644 "${REDIR_CONFIG_FILES[@]}"
    copy_dashboards
}

render_logstash_settings() {
    print_section "Rendering Logstash Settings"
    cat > "${ELK_ROOT}/logstash/logstash.yml" <<'EOF'
http.host: "0.0.0.0"
xpack.monitoring.enabled: false
EOF
    chmod 0644 "${ELK_ROOT}/logstash/logstash.yml"

    cat > "$PIPELINE_CONFIG" <<'EOF'
- pipeline.id: main
  path.config: /usr/share/logstash/pipeline
EOF
    chmod 0644 "$PIPELINE_CONFIG"
}

deploy_logstash_configs() {
    print_section "Deploying Logstash Pipelines"
    mkdir -p "$PIPELINE_DIR"
    find "$PIPELINE_DIR" -maxdepth 1 -type f -name '*.conf' -exec rm -f {} +
    local deployed=0
    for name in "${LOGSTASH_CONF_FILES[@]}"; do
        local src="${CONF_DEST_DIR}/${name}"
        local dest="${PIPELINE_DIR}/${name}"
        if [[ ! -f "$src" ]]; then
            fatal "Missing source pipeline ${src}"
        fi
        printf '[INFO] Deploy %s -> %s\n' "$src" "$dest"
        install -m 0644 "$src" "$dest"
        ((deployed++))
    done
    log_info "Command: ls -1 ${PIPELINE_DIR}/*.conf | wc -l"
    local dest_count
    dest_count=$(ls -1 "${PIPELINE_DIR}"/*.conf | wc -l)
    printf 'conf_count_pipelines=%s\n' "$dest_count"
    if (( dest_count != deployed )); then
        fatal "Logstash pipeline deployment mismatch"
    fi
    log_info "Pipeline load order:"
    for name in "${LOGSTASH_CONF_FILES[@]}"; do
        printf '  %s\n' "$name"
    done
}

create_env_file() {
    print_section "Rendering Compose Environment"
    cat > "${ELK_ROOT}/.env" <<EOF
ELASTIC_VERSION=${ELASTIC_VERSION}
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
REDELK_VERSION=${REDELK_VERSION}
ES_JAVA_OPTS=${ES_JAVA_OPTS}
LS_JAVA_OPTS=${LS_JAVA_OPTS}
REDELK_PATH=${REDELK_PATH}
ELASTICSEARCH_HOSTS=http://elasticsearch:9200
COMPOSE_PROJECT_NAME=redelk
EOF
    chmod 0640 "${ELK_ROOT}/.env"
}

create_kibana_config() {
    print_section "Rendering Kibana Configuration"
    cat > "${CONFIG_DIR}/kibana.yml" <<EOF
server.host: "0.0.0.0"
server.publicBaseUrl: "https://localhost"
elasticsearch.hosts: ["http://elasticsearch:9200"]
elasticsearch.username: "elastic"
elasticsearch.password: "${ELASTIC_PASSWORD}"
telemetry.enabled: false
xpack.fleet.enabled: true
EOF
    chmod 0640 "${CONFIG_DIR}/kibana.yml"
}

create_nginx_config() {
    print_section "Rendering Nginx Reverse Proxy Configuration"
    cat > "${NGINX_DIR}/kibana.conf" <<'EOF'
server {
    listen 80;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/nginx/certs/elkserver.crt;
    ssl_certificate_key /etc/nginx/certs/elkserver.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/htpasswd;

    location / {
        proxy_pass http://kibana:5601;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    chmod 0644 "${NGINX_DIR}/kibana.conf"

    if [[ ! -f "${NGINX_DIR}/htpasswd" ]]; then
        log_info "Creating default htpasswd for Nginx (user: redelk)"
        printf 'redelk:$apr1$h2/2Y0dN$4wB7lYfovnEwlHGawEqPG1\n' > "${NGINX_DIR}/htpasswd"
    fi
    chmod 0640 "${NGINX_DIR}/htpasswd"
}

generate_certificates() {
    print_section "Generating TLS Certificates"
    local key="${CERT_DIR}/elkserver.key"
    local crt="${CERT_DIR}/elkserver.crt"
    if [[ -f "$key" && -f "$crt" ]]; then
        log_info "Existing certificates found; skipping generation"
        return
    fi
    openssl req -x509 -nodes -newkey rsa:4096 \
        -keyout "$key" \
        -out "$crt" \
        -days 825 \
        -subj "/CN=redelk.local/O=RedELK/OU=Automation"
    chmod 0600 "$key"
    chmod 0644 "$crt"
    log_info "Generated self-signed TLS certificate at ${crt}"
}

create_docker_compose() {
    print_section "Rendering docker-compose.yml"
    cat > "${ELK_ROOT}/docker-compose.yml" <<'EOF'
version: '3.8'

networks:
  redelk:
    driver: bridge

volumes:
  elasticsearch-data:
  logstash-data:

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ELASTIC_VERSION}
    container_name: redelk-elasticsearch
    restart: unless-stopped
    environment:
      - node.name=redelk-node-1
      - cluster.name=redelk-cluster
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=false
      - xpack.security.transport.ssl.enabled=false
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
      - elasticsearch-data:/usr/share/elasticsearch/data
      - ./elasticsearch/index-templates:/usr/share/elasticsearch/config/index-templates:ro
      - ../certs:/usr/share/elasticsearch/config/certs:ro
      - ./logs/elasticsearch:/usr/share/elasticsearch/logs
    ports:
      - "127.0.0.1:9200:9200"
      - "127.0.0.1:9300:9300"
    networks:
      - redelk
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 40
      start_period: 120s

  logstash:
    image: docker.elastic.co/logstash/logstash:${ELASTIC_VERSION}
    container_name: redelk-logstash
    restart: unless-stopped
    environment:
      - LS_JAVA_OPTS=${LS_JAVA_OPTS}
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - ELASTICSEARCH_HOSTS=${ELASTICSEARCH_HOSTS}
    volumes:
      - ./logstash/pipelines:/usr/share/logstash/pipeline:ro
      - ./logstash/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
      - ./logstash/pipelines.yml:/usr/share/logstash/config/pipelines.yml:ro
      - ./elasticsearch/index-templates:/usr/share/logstash/config/index-templates:ro
      - ./logstash/threat-feeds:/usr/share/logstash/config/threat-feeds:ro
      - logstash-data:/usr/share/logstash/data
      - ./logs/logstash:/usr/share/logstash/logs
    ports:
      - "0.0.0.0:5044:5044"
      - "127.0.0.1:9600:9600"
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - redelk
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:9600/_node/pipelines || exit 1"]
      interval: 20s
      timeout: 5s
      retries: 40
      start_period: 90s

  kibana:
    image: docker.elastic.co/kibana/kibana:${ELASTIC_VERSION}
    container_name: redelk-kibana
    restart: unless-stopped
    environment:
      - ELASTICSEARCH_HOSTS=${ELASTICSEARCH_HOSTS}
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - SERVER_NAME=kibana
    volumes:
      - ./config/kibana.yml:/usr/share/kibana/config/kibana.yml:ro
      - ./kibana/dashboards:/usr/share/kibana/dashboards:ro
      - ./logs/kibana:/usr/share/kibana/logs
    ports:
      - "127.0.0.1:5601:5601"
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - redelk
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:5601/api/status | grep -q '"level":"available"'"]
      interval: 20s
      timeout: 10s
      retries: 80
      start_period: 180s

  nginx:
    image: nginx:1.27-alpine
    container_name: redelk-nginx
    restart: unless-stopped
    volumes:
      - ./nginx/kibana.conf:/etc/nginx/conf.d/default.conf:ro
      - ./nginx/htpasswd:/etc/nginx/htpasswd:ro
      - ../certs:/etc/nginx/certs:ro
      - ./logs/nginx:/var/log/nginx
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      kibana:
        condition: service_started
    networks:
      - redelk
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
EOF
    chmod 0644 "${ELK_ROOT}/docker-compose.yml"
}

validate_logstash_configs() {
    print_section "Validating Logstash Configuration"
    local image="docker.elastic.co/logstash/logstash:${ELASTIC_VERSION}"
    local cmd=(docker run --rm -v "${PIPELINE_DIR}:/usr/share/logstash/pipeline:ro" "$image" --config.test_and_exit)
    log_info "Running: ${cmd[*]}"
    local output
    if ! output=$("${cmd[@]}" 2>&1); then
        printf '%s\n' "$output"
        fatal "Logstash configuration validation failed"
    fi
    printf '%s\n' "$output"
    log_info "Logstash configuration validation succeeded"
}

start_stack() {
    print_section "Starting Docker Stack"
    (cd "$ELK_ROOT" && "${COMPOSE_CMD[@]}" pull)
    (cd "$ELK_ROOT" && "${COMPOSE_CMD[@]}" up -d --remove-orphans)
    (cd "$ELK_ROOT" && "${COMPOSE_CMD[@]}" ps)
}

wait_for_elasticsearch() {
    print_section "Waiting for Elasticsearch"
    local attempt=0
    while (( attempt < 60 )); do
        local response
        if response=$(curl -s -u "elastic:${ELASTIC_PASSWORD}" http://127.0.0.1:9200/_cluster/health); then
            local status
            status=$(printf '%s' "$response" | jq -r '.status' 2>/dev/null || echo "unknown")
            printf '[INFO] attempt %02d: cluster status=%s\n' "$attempt" "$status"
            if [[ "$status" == "yellow" || "$status" == "green" ]]; then
                log_info "Elasticsearch is ready (status ${status})"
                return
            fi
        fi
        sleep 5
        ((attempt++))
    done
    fatal "Elasticsearch did not become ready within timeout"
}

deploy_elasticsearch_templates() {
    print_section "Deploying Elasticsearch Index Templates"
    for name in "${TEMPLATE_FILES[@]}"; do
        local file="${TEMPLATE_DEST_DIR}/${name}"
        local template_name="${name%.json}"
        log_info "Uploading template ${template_name} from ${file}"
        local response
        response=$(curl -sS -u "elastic:${ELASTIC_PASSWORD}" \
            -H 'Content-Type: application/json' \
            -X PUT "http://127.0.0.1:9200/_index_template/${template_name}" \
            --data-binary "@${file}")
        printf '%s\n' "$response"
        if ! echo "$response" | jq -e '.acknowledged == true' >/dev/null 2>&1; then
            fatal "Failed to upload template ${template_name}"
        fi
    done
}

import_kibana_dashboards() {
    print_section "Importing Kibana Dashboards"
    local imported=0
    for name in "${DASHBOARD_FILES[@]}"; do
        local path="${DASHBOARD_DEST_DIR}/${name}"
        local size
        size=$(stat -c '%s' "$path")
        log_info "Importing ${path} (${size} bytes)"
        local response
        response=$(curl -sS -u "elastic:${ELASTIC_PASSWORD}" \
            -H 'kbn-xsrf: redelk' \
            -F file=@"${path}" \
            "http://127.0.0.1:5601/api/saved_objects/_import?overwrite=true")
        printf '%s\n' "$response"
        if ! echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
            fatal "Kibana dashboard import failed for ${name}"
        fi
        ((imported++))
    done
    log_info "Imported ${imported} Kibana dashboard file(s)"
}

postflight_checks() {
    print_section "Post-Flight Validation"
    log_info "Checking Elasticsearch cluster health"
    local health
    health=$(curl -sS -u "elastic:${ELASTIC_PASSWORD}" "http://127.0.0.1:9200/_cluster/health")
    printf '%s\n' "$health"
    local status
    status=$(printf '%s' "$health" | jq -r '.status')
    if [[ "$status" != "yellow" && "$status" != "green" ]]; then
        fatal "Elasticsearch health status ${status} is not acceptable"
    fi

    log_info "Listing Elasticsearch indices"
    curl -sS -u "elastic:${ELASTIC_PASSWORD}" "http://127.0.0.1:9200/_cat/indices?v"

    log_info "Querying Logstash node pipelines"
    curl -sS "http://127.0.0.1:9600/_node/pipelines"

    log_info "Checking Beats input port 5044"
    if ss -ltn | grep -q ':5044'; then
        log_info "Port 5044 is listening"
    else
        fatal "Logstash Beats port 5044 is not listening"
    fi

    log_info "Checking Kibana status API"
    local kstatus
    kstatus=$(curl -sS "http://127.0.0.1:5601/api/status" | jq -r '.status.overall.level')
    log_info "Kibana status: ${kstatus}"
    if [[ "$kstatus" != "available" ]]; then
        fatal "Kibana status is ${kstatus} (expected available)"
    fi
}

main() {
    require_root
    setup_logging
    print_section "RedELK ${REDELK_VERSION} Deployment"
    log_info "Start timestamp: ${RUN_TIMESTAMP}"
    log_info "Bundle path: ${SCRIPT_DIR}"
    load_source_manifests
    detect_os
    install_dependencies
    ensure_docker
    preflight_checks
    prepare_directories
    copy_deployment_files
    render_logstash_settings
    deploy_logstash_configs
    create_env_file
    create_kibana_config
    create_nginx_config
    generate_certificates
    create_docker_compose
    validate_logstash_configs
    start_stack
    wait_for_elasticsearch
    deploy_elasticsearch_templates
    import_kibana_dashboards
    postflight_checks
    print_section "Deployment Complete"
    log_info "Completed at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

main "$@"
