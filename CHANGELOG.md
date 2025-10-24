# RedELK Changelog

All notable changes to RedELK are documented in this file.

## [3.0.0] - 2024-10-24

### 🎉 Major Release - Complete Modernization

Version 3.0.0 represents a complete modernization of RedELK with focus on ease of use, reliability, and modern deployment practices.

### ✨ New Features

#### Installation & Deployment
- **Modern Python Installer** (`install.py`)
  - Interactive installation wizard with helpful prompts
  - Pre-flight system checks (memory, disk, Docker, ports)
  - Progress bars and visual feedback
  - Smart defaults with auto-detection
  - Quick start mode for rapid deployment
  - Dry-run mode for validation

- **Unified Agent Installer** (`install-agent.py`)
  - Single installer for both C2 servers and redirectors
  - Interactive configuration
  - Automatic Filebeat installation and configuration
  - Connection testing

- **Certificate Generator** (`scripts/generate-certificates.py`)
  - Automated TLS certificate generation
  - Interactive or automatic mode
  - Support for multiple DNS names and IPs
  - Simplified from complex bash scripts

#### Management & Operations
- **RedELK CLI Tool** (`./redelk`)
  - Service management: status, start, stop, restart
  - Log viewing: logs, tail, follow
  - Information: passwords, urls, health, info
  - Maintenance: update, clean
  - Shell access to containers

- **Makefile Commands**
  - 30+ convenient shortcuts
  - Organized by category (installation, service management, diagnostics)
  - Color-coded output
  - Help system with descriptions

### 📦 Technology Upgrades

#### ELK Stack
- **Elasticsearch**: 7.17.9 → 8.11.3
- **Logstash**: 7.17.9 → 8.11.3
- **Kibana**: 7.17.9 → 8.11.3
- **Filebeat**: 7.17.9 → 8.11.3

#### Docker & Compose
- **Docker Compose**: v3.3 → v3.8
  - Modern syntax and features
  - Health checks for all services
  - Service dependencies with health conditions
  - Resource limits (memory, CPU)
  - Fixed IP addresses in Docker network
  - Better restart policies

#### Docker Images
- **Neo4j**: 4.4 → 5.15-community
- **PostgreSQL**: 13.2 → 15-alpine
- **NGINX**: latest → 1.25-alpine (pinned)
- All images now have specific version tags

### 🏥 Health & Monitoring

#### Health Checks
- Elasticsearch: Cluster health endpoint
- Logstash: Node stats API
- Kibana: Status API
- All other services: Appropriate health checks
- `./redelk health` command for overview

#### Service Dependencies
- Services start in correct order
- Wait for dependencies to be healthy
- Automatic recovery from failures
- Better error messages

### 📚 Documentation

#### New Documentation
- **Quick Start Guide** (`docs/QUICKSTART.md`)
  - 5-minute setup guide
  - Multiple installation options
  - Common operations
  - Troubleshooting basics

- **Architecture Guide** (`docs/ARCHITECTURE.md`)
  - Component overview
  - Data flow diagrams
  - Network topology
  - Security architecture
  - Deployment models

- **Troubleshooting Guide** (`docs/TROUBLESHOOTING.md`)
  - Common issues and solutions
  - Diagnostic commands
  - Service-specific troubleshooting
  - Emergency recovery procedures

#### Updated Documentation
- **README.md** - Complete rewrite with v3.0 features
- **VERSION** - Updated to 3.0.0
- Inline code comments improved
- Template files documented

### 🎨 User Experience

#### Terminal UI
- Color-coded output (green=success, yellow=warning, red=error)
- Progress bars for long operations
- Tables for structured data
- Panels for sections
- Consistent formatting

#### Error Messages
- Clear, actionable error messages
- Solutions provided with errors
- Proper exit codes
- Verbose mode for debugging

#### Interactive Prompts
- Smart defaults
- Validation of inputs
- Contextual help
- Example values
- Confirmation before destructive operations

### 🔒 Security Improvements

#### Certificates
- Automated generation
- PKCS8 format support
- SAN (Subject Alternative Name) properly configured
- CA certificate distribution simplified

#### Passwords
- Auto-generated secure passwords (32 characters)
- Stored in `redelk_passwords.cfg`
- No default passwords
- Passwords shown after installation

#### TLS
- TLS 1.3 support
- Let's Encrypt integration improved
- Certificate verification
- Secure defaults

### 🐛 Bug Fixes

#### Installation
- Fixed sed escaping issues in bash scripts
- Proper permission handling
- Better error detection
- Cleanup of temporary files

#### Docker
- Fixed race conditions in service startup
- Proper volume permissions
- Network isolation improved
- Resource limit handling

#### Configuration
- Template variable substitution improved
- .env file generation more reliable
- Config validation added

### ⚡ Performance Improvements

#### Memory Management
- Auto-calculated memory limits based on system RAM
- Configurable memory settings in `.env`
- Better JVM heap sizing
- Resource limits enforced

#### Startup Time
- Parallel service initialization where possible
- Health-based dependencies reduce waiting
- Faster image builds (when implemented)

### 🔧 Configuration

#### Environment Variables
- Comprehensive `.env.template` (stored as `env.template`)
- Inline documentation
- Sensible defaults
- Easy customization

#### Docker Compose
- `redelk-full-v3.yml` - Modern full installation
- Separate network with fixed IPs
- Health checks integrated
- Resource limits configurable

### 📝 Breaking Changes

⚠️ **Version 3.0.0 introduces breaking changes from v2.x:**

1. **Installation Method Changed**
   - Old: `./initial-setup.sh` + `./install-elkserver.sh`
   - New: `python3 install.py`

2. **Docker Compose Version**
   - Requires Docker Compose v2 (plugin version)
   - Old standalone `docker-compose` still supported

3. **ELK Stack Version**
   - Upgraded to 8.x (from 7.x)
   - May require data migration for existing deployments
   - API changes in Elasticsearch 8.x

4. **Configuration Files**
   - New `.env` template structure
   - Some paths changed
   - Certificate locations standardized

5. **Agent Installation**
   - Old: Separate scripts for C2 and redirectors
   - New: Unified `install-agent.py`

### 🔄 Migration from v2.x

For users upgrading from v2.x:

1. **Backup your data** before upgrading
2. **Review new configuration** in `env.template`
3. **Test in staging** before production upgrade
4. **Update agents** on C2 servers and redirectors
5. See [UPGRADING.md] for detailed migration guide (TODO)

### 🙏 Acknowledgments

- Original RedELK team at Outflank B.V.
- Contributors to v2.x
- Community feedback and bug reports
- ELK Stack development team

### 📊 Statistics

- **Lines of Code**: ~10,000+ (new Python code)
- **New Files**: 15+ (installers, docs, CLI, Makefile)
- **Docker Images**: 9 containers
- **Documentation**: 4 comprehensive guides
- **Installation Time**: ~5-10 minutes (from ~30+ minutes)
- **Commands**: 30+ Make targets, 15+ CLI commands

## [2.0.0-beta.6] - Previous Release

See git history for previous releases.

---

## Legend

- ✨ New Feature
- 🐛 Bug Fix
- 📚 Documentation
- ⚡ Performance
- 🔒 Security
- 💥 Breaking Change
- 🔧 Configuration
- 🎨 UI/UX



