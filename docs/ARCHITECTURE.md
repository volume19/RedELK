# RedELK v3.0 Architecture

This document describes the technical architecture of RedELK.

## Overview

RedELK is a Red Team SIEM (Security Information and Event Management) system designed to:
1. **Aggregate** logs from Command & Control (C2) servers and redirectors
2. **Enrich** data with threat intelligence and context
3. **Detect** Blue Team investigation activities
4. **Visualize** operations through interactive dashboards
5. **Alert** operators when potential compromise is detected

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            Red Team Infrastructure                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐                  │
│  │   C2 Server │   │   C2 Server │   │ Redirector  │                  │
│  │  (Cobalt    │   │  (Sliver)   │   │  (HAProxy)  │                  │
│  │   Strike)   │   │             │   │             │                  │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘                  │
│         │                 │                 │                          │
│         │ Filebeat        │ Filebeat        │ Filebeat                 │
│         │ (logs)          │ (logs)          │ (traffic)                │
│         │                 │                 │                          │
└─────────┼─────────────────┼─────────────────┼──────────────────────────┘
          │                 │                 │
          │     TLS 5044    │                 │
          └─────────────────┴─────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          RedELK Server (ELK Stack)                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                          NGINX (Port 80/443)                       │ │
│  │               Reverse Proxy & TLS Termination                      │ │
│  └─────────┬─────────────────────┬────────────────────┬───────────────┘ │
│            │                     │                    │                 │
│  ┌─────────▼────────┐  ┌────────▼────────┐  ┌────────▼────────┐       │
│  │     Kibana       │  │   Jupyter       │  │  BloodHound     │       │
│  │   (Port 5601)    │  │  (Port 8888)    │  │  (Port 8080)    │       │
│  │  Visualization   │  │   Analysis      │  │  AD Paths       │       │
│  └─────────┬────────┘  └─────────────────┘  └────────┬────────┘       │
│            │                                          │                │
│            │                                          │                │
│  ┌─────────▼──────────────────────────────────────────────────┐       │
│  │              Elasticsearch (Port 9200)                     │       │
│  │              - Data Storage                                 │       │
│  │              - Search Engine                                │       │
│  │              - Index Management                             │       │
│  └─────────▲──────────────────────────────────────────────────┘       │
│            │                              │                            │
│  ┌─────────┴────────┐         ┌──────────▼─────────┐                  │
│  │    Logstash      │         │   RedELK Base      │                  │
│  │  (Port 5044)     │         │   - Enrichment     │                  │
│  │  - Log Ingestion │         │   - Alarms         │                  │
│  │  - Parsing       │         │   - Cron Jobs      │                  │
│  │  - Filtering     │         │   - C2 Sync        │                  │
│  └──────────────────┘         └────────────────────┘                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Data Collection Layer

#### Filebeat Agents
- **Location:** Installed on C2 servers and redirectors
- **Function:** 
  - Monitors log files for changes
  - Ships logs securely via TLS to Logstash
  - Handles connection retry and buffering
- **Configuration:**
  - C2 servers: Monitor C2 framework logs (Cobalt Strike, Sliver, PoshC2, etc.)
  - Redirectors: Monitor web server logs (Apache, Nginx, HAProxy)

#### Supported C2 Frameworks
- Cobalt Strike
- Sliver
- PoshC2 (PowerShell C2)
- Outflank Stage1 Tool
- Custom frameworks (via custom Logstash filters)

### 2. Ingestion & Processing Layer

#### Logstash
- **Function:**
  - Receives logs from Filebeat agents (port 5044)
  - Parses and structures log data
  - Enriches with metadata (GeoIP, timestamps, etc.)
  - Routes to appropriate Elasticsearch indices
  
- **Processing Pipeline:**
  ```
  Input (Filebeat) → Parse → Enrich → Filter → Output (Elasticsearch)
  ```

- **Key Processing Steps:**
  1. **Parsing:** Extract fields from raw logs
  2. **Enrichment:** Add GeoIP, DNS resolution, etc.
  3. **Categorization:** Tag by attack scenario, C2 type, etc.
  4. **Filtering:** Remove noise, apply whitelists
  5. **Indexing:** Route to appropriate ES index

### 3. Storage Layer

#### Elasticsearch
- **Function:**
  - Stores all processed log data
  - Provides search and analytics capabilities
  - Manages data lifecycle (ILM policies)
  
- **Index Structure:**
  ```
  redelk-*          # Main operational logs
  redirtraffic-*    # Redirector traffic logs
  rtops-*           # Real-time operations data
  credentials-*     # Harvested credentials
  bluecheck-*       # Blue team detection events
  email-*           # Email notifications log
  implantsdb-*      # Implant metadata
  iplist-*          # IP watchlists
  ```

- **Data Retention:**
  - Configurable via ILM (Index Lifecycle Management)
  - Default: 30 days for traffic, 90 days for operations

### 4. Visualization Layer

#### Kibana
- **Function:**
  - Primary user interface
  - Interactive dashboards
  - Search and filtering
  - Alert management
  
- **Key Dashboards:**
  1. **Overview:** High-level operation summary
  2. **Traffic Analysis:** Redirector traffic patterns
  3. **Beacon Activity:** C2 callback tracking
  4. **IOC Tracking:** Indicators of Compromise
  5. **Blue Team Detection:** Potential investigation activity
  6. **MITRE ATT&CK:** Technique coverage
  7. **Screenshots:** Visual artifacts from targets
  8. **Downloads:** Exfiltrated files
  9. **Keystrokes:** Captured keystrokes
  10. **Tasks:** C2 commands issued

#### Jupyter Notebooks (Full Install)
- **Function:**
  - Ad-hoc analysis
  - Custom queries
  - Data exploration
  - Report generation
  
- **Use Cases:**
  - Statistical analysis of traffic
  - Custom visualizations
  - Automated reporting
  - Data export

#### BloodHound (Full Install)
- **Function:**
  - Active Directory attack path analysis
  - Relationship mapping
  - Privilege escalation paths
  
- **Components:**
  - BloodHound CE (Community Edition)
  - Neo4j graph database
  - PostgreSQL for metadata

### 5. Enrichment & Alert Layer

#### RedELK Base Container
- **Function:**
  - Background enrichment tasks
  - Alarm generation
  - Scheduled jobs
  - External API integration
  
- **Enrichment Modules:**
  1. **GeoIP:** Location data for IPs
  2. **GreyNoise:** Internet scanner detection
  3. **Tor Exit Nodes:** Tor network identification
  4. **VirusTotal:** File hash reputation
  5. **IBM X-Force:** Threat intelligence
  6. **Hybrid Analysis:** Malware sandbox results
  7. **Domain Categorization:** Website classification
  
- **Alarm Modules:**
  1. **File Hash Alarm:** Detects known IOCs
  2. **HTTP Traffic Alarm:** Suspicious traffic patterns
  3. **User Agent Alarm:** Unusual user agents
  4. **Backend Alarm:** Backend investigation activity
  5. **Manual Alarm:** Operator-triggered alerts

#### Notification Channels
- Email (SMTP)
- Slack webhooks
- Microsoft Teams webhooks
- Custom webhooks (extensible)

### 6. Web Layer

#### NGINX
- **Function:**
  - Reverse proxy for all web services
  - TLS termination
  - Load balancing
  - Access control
  
- **Routes:**
  ```
  /              → Kibana (main dashboard)
  /jupyter       → Jupyter notebooks
  :8443          → BloodHound
  :7474          → Neo4j browser
  ```

- **TLS Options:**
  1. Let's Encrypt (automated certificates)
  2. Self-signed (auto-generated)
  3. Custom certificates (provided by user)

#### Certbot (Optional)
- **Function:**
  - Automated Let's Encrypt certificate management
  - Certificate renewal
  
- **Renewal:** Every 12 hours (checks if renewal needed)

## Data Flow

### C2 Operations → RedELK

```
┌─────────────────┐
│  C2 Framework   │ Generates logs
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Filebeat Agent │ Monitors log files
└────────┬────────┘
         │ TLS Port 5044
         ▼
┌─────────────────┐
│    Logstash     │ Parses & enriches
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Elasticsearch   │ Stores & indexes
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ RedELK Base     │ Enriches & alerts
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Kibana/Jupyter │ Visualizes
└─────────────────┘
```

### Redirector Traffic → RedELK

```
┌──────────────────┐
│  Target Traffic  │ HTTP/HTTPS requests
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Redirector Proxy │ Logs all traffic
│  (Apache/HAProxy)│
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Filebeat Agent  │ Ships logs
└────────┬─────────┘
         │ TLS Port 5044
         ▼
┌──────────────────┐
│    Logstash      │ Parses traffic
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Elasticsearch    │ Analyzes patterns
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Blue Detection  │ Alerts on anomalies
└──────────────────┘
```

## Network Architecture

### Ports

#### External (Internet-facing)
- `80/tcp` - HTTP (redirect to HTTPS, Let's Encrypt)
- `443/tcp` - HTTPS (Kibana, Jupyter)
- `5044/tcp` - Logstash Beats input (TLS)
- `8443/tcp` - BloodHound (HTTPS)
- `7474/tcp` - Neo4j browser (optional, can be firewalled)

#### Internal (Docker network)
- `9200/tcp` - Elasticsearch HTTP API
- `9300/tcp` - Elasticsearch transport (cluster)
- `5601/tcp` - Kibana
- `8888/tcp` - Jupyter
- `9600/tcp` - Logstash API
- `5432/tcp` - PostgreSQL
- `7687/tcp` - Neo4j Bolt protocol

### Network Topology

```
┌────────────────────────────────────────────────────┐
│              Internet / Team Network               │
└──────────┬─────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────┐
│                   Firewall / Security                │
│  Rules: Allow 80, 443, 5044, 8443 (optionally 7474) │
└──────────┬───────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────┐
│                  RedELK Server (Host)                │
│  └─────────────────────────────────────────┐         │
│  │      Docker Network (172.28.0.0/16)     │         │
│  │                                          │         │
│  │  [NGINX]   [ES]   [Kibana]  [Logstash] │         │
│  │  .40       .10    .30        .20        │         │
│  │                                          │         │
│  │  [Base]  [Jupyter]  [Neo4j]  [BH]      │         │
│  └──────────────────────────────────────────┘        │
└───────────────────────────────────────────────────────┘
```

### TLS/SSL

#### Certificate Hierarchy
```
redelkCA (Self-signed Root CA)
├── elkserver.crt (Logstash input)
├── redelk-elasticsearch.crt
├── redelk-kibana.crt
└── redelk-logstash.crt (internal)

Let's Encrypt CA (Optional, for NGINX)
└── YOUR_DOMAIN.crt
```

## Security Architecture

### Authentication & Authorization

#### Elasticsearch
- Built-in user authentication
- Role-based access control (RBAC)
- Users:
  - `elastic` - Superuser
  - `kibana_system` - Kibana service account
  - `logstash_system` - Logstash service account
  - `redelk` - Main operator account
  - `redelk_ingest` - Data ingestion account

#### Kibana
- Authenticates against Elasticsearch
- HTTP Basic Auth via NGINX
- Username/password from .env file

#### Neo4j/BloodHound
- Separate authentication
- Neo4j: username/password
- BloodHound: admin account

### Encryption

#### In Transit
- All external communication via TLS 1.3
- Filebeat → Logstash: TLS with client certificate verification
- Browser → NGINX: HTTPS
- Internal Docker: TLS between ELK components

#### At Rest
- Docker volumes (can be encrypted at host level)
- Elasticsearch indices (can enable encryption at rest)
- Certificates stored in mounted volumes

### Network Segmentation

```
External Network    Docker Network    Service Network
    (0.0.0.0)    →   (172.28.0.0)  →  (localhost)

Agents connect  →  NGINX/Logstash  →  Internal services
to public IPs      in Docker net      on localhost only
```

## Scalability Considerations

### Vertical Scaling
- **Memory:** Increase ES_MEMORY for more data
- **CPU:** More cores = faster processing
- **Disk:** SSD recommended for Elasticsearch

### Horizontal Scaling (Future)
- Elasticsearch cluster (multiple nodes)
- Logstash load balancing
- Multiple RedELK servers per operation

### Performance Tuning
- JVM heap sizing (50% of available RAM, max 31GB)
- Elasticsearch shard configuration
- Logstash pipeline workers
- Docker resource limits

## Monitoring & Health

### Health Checks
- All containers have health checks
- Docker native health monitoring
- `./redelk health` command

### Logs
- Container logs: `docker logs`
- Application logs: `elkserver/mounts/redelk-logs/`
- JSON structured logging

### Metrics (Future)
- Elasticsearch monitoring
- Logstash pipeline metrics
- Custom metrics via Metricbeat

## Deployment Models

### Single Server (Current)
- All components on one host
- Suitable for small to medium operations
- Resource requirements: 8GB RAM, 4 CPU cores, 100GB disk

### Distributed (Future)
- Elasticsearch cluster across multiple nodes
- Dedicated Logstash nodes
- Load balanced Kibana
- Resource requirements: Scale based on load

### Cloud (Future)
- AWS/Azure/GCP deployment
- Managed Elasticsearch service option
- Auto-scaling capabilities

## Data Lifecycle

### Ingestion
1. Filebeat buffers logs locally
2. Ships to Logstash over TLS
3. Logstash processes and indexes
4. Elasticsearch stores and indexes

### Retention
- Traffic logs: 30 days (configurable)
- Operational logs: 90 days (configurable)
- Credentials: Indefinite
- IOCs: Indefinite

### Archival
- Manual backup via `make backup`
- Elasticsearch snapshot/restore
- Export to external systems

## Extension Points

### Custom C2 Frameworks
1. Create Filebeat config in `c2servers/filebeat/inputs.d/`
2. Add Logstash filter in `elkserver/mounts/logstash-config/redelk-main/conf.d/`
3. Define field mappings

### Custom Enrichment
1. Add Python module in `elkserver/docker/redelk-base/redelkinstalldata/scripts/modules/`
2. Register in `config.json`
3. Configure cron schedule

### Custom Alarms
1. Create alarm module (similar to existing)
2. Define alarm logic
3. Configure notification channels

### Custom Dashboards
1. Create in Kibana UI
2. Export as NDJSON
3. Include in deployment templates

## Dependencies

### Core
- Docker 20.10+
- Docker Compose v2.0+
- Python 3.8+
- 8GB RAM (minimum)
- 100GB disk space

### Docker Images
- elasticsearch:8.11.3
- logstash:8.11.3
- kibana:8.11.3
- nginx:1.25-alpine
- neo4j:5.15-community
- postgres:15-alpine
- specterops/bloodhound:latest
- certbot/certbot:latest

### Python Packages (Base Container)
- elasticsearch
- requests
- jinja2
- pyyaml
- python-dateutil

## Future Enhancements

### Planned Features
- Kubernetes deployment option
- Multi-tenant support
- Real-time collaboration features
- Enhanced ML-based detection
- Integrated threat hunting workflows
- API for external integrations

### Community Contributions
- Additional C2 framework support
- New enrichment modules
- Custom alarm logic
- Dashboard improvements

---

**Version:** 3.0.0  
**Last Updated:** October 2024  
**Maintainers:** Outflank B.V. / RedELK Development Team


