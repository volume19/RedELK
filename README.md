![Build docker base image (dev)](https://github.com/outflanknl/RedELK/workflows/Build%20docker%20base%20image%20(dev)/badge.svg?branch=maindev)
![Build docker elasticsearch image (dev)](https://github.com/outflanknl/RedELK/workflows/Build%20docker%20elasticsearch%20image%20(dev)/badge.svg?branch=maindev)
![Build docker jupyter image (dev)](https://github.com/outflanknl/RedELK/workflows/Build%20docker%20jupyter%20image%20(dev)/badge.svg?branch=maindev)
![Build docker kibana image (dev)](https://github.com/outflanknl/RedELK/workflows/Build%20docker%20kibana%20image%20(dev)/badge.svg?branch=maindev)
![Build docker logstash image (dev)](https://github.com/outflanknl/RedELK/workflows/Build%20docker%20logstash%20image%20(dev)/badge.svg?branch=maindev)

# RedELK v3.0 - Modernized Red Team SIEM

> **🎉 Version 3.0** brings massive improvements to deployment, reliability, and user experience!

Red Team's SIEM - A comprehensive tool for Red Teams enabling tracking and alarming about Blue Team activities, plus enhanced usability in long-term operations.

## Core Capabilities

1. **Enhanced usability and overview** - Central location for all relevant _operational_ logs from multiple teamservers. Perfect for historic searching, read-only operational views (e.g., White Team), and multi-scenario/multi-month operations. Easy access to screenshots, IOCs, keystrokes, and more. \o/

2. **Spot the Blue Team** - Central collection of all _traffic_ logs from redirectors with enrichment. Detect Blue Team investigation activities through specific queries and automated alarms.

## 🆕 What's New in v3.0

### Simplified Installation
- **🚀 One-Command Install**: `sudo python3 install.py --quickstart`
- **Interactive Installer**: User-friendly prompts with validation and helpful explanations
- **Pre-flight Checks**: Automatic system validation before installation
- **Progress Tracking**: Visual progress bars and clear step-by-step indicators
- **Auto-Configuration**: Smart defaults with auto-detection of system settings

### Modern Technology Stack
- **⬆️ ELK 8.x**: Upgraded from 7.17.9 to Elasticsearch/Kibana/Logstash 8.11.3
- **🐳 Docker Compose v3.8**: Modern syntax with comprehensive health checks
- **✅ Health Monitoring**: All services include health checks and status reporting
- **🔄 Better Orchestration**: Services start in the correct order with dependency management

### Enhanced User Experience
- **📊 Rich Terminal UI**: Color-coded output with tables, progress bars, and panels
- **🛠️ Management CLI**: `./redelk` command for easy service management
- **📖 Comprehensive Docs**: Quick Start, Troubleshooting, and Architecture guides
- **🎯 Better Error Messages**: Clear, actionable error messages with solutions
- **⚡ Makefile Commands**: Quick shortcuts like `make status`, `make logs`, `make restart`

### Improved Deployment
- **🔐 Auto-Generated Certificates**: Simplified TLS certificate creation
- **🤖 Unified Agent Installer**: Single tool for both C2 servers and redirectors
- **📦 Template System**: Clean `.env.template` with inline documentation
- **🔍 Configuration Validation**: Pre-deployment validation of all settings
- **💾 Backup & Restore**: Built-in backup capabilities

### Better Reliability
- **🏥 Health Checks**: Continuous monitoring of all services
- **🔄 Smart Restarts**: Automatic recovery from common failures
- **📊 Resource Limits**: Configurable memory and CPU constraints
- **🌐 Network Optimization**: Improved Docker networking with fixed IPs
- **📝 Structured Logging**: JSON logs with rotation and filtering

# Background info #
Check the [wiki](https://github.com/outflanknl/RedELK/wiki) for info on usage or one the blog posts or presentations listed below:
- Blog part 1: [Why we need RedELK](https://outflank.nl/blog/2019/02/14/introducing-redelk-part-1-why-we-need-it/)
- Blog part 2: [Getting you up and running](https://outflank.nl/blog/2020/02/28/redelk-part-2-getting-you-up-and-running/)
- Blog part 3: [Achieving operational oversight](https://outflank.nl/blog/2020/04/07/redelk-part-3-achieving-operational-oversight/)
- SANS Hackfest 2020: Super charge your Red Team with RedELK [video](https://www.youtube.com/watch?v=24pVnDSSOLY) and [slides](https://github.com/outflanknl/Presentations/blob/master/SANSHackFest2020_Smeets_SuperchargeYourRedTeamwithRedELK.pdf)
- Hack in Paris 2019: Who watches the Watchmen [video](https://www.youtube.com/watch?v=ZezBCAUax6c) and [slides](https://github.com/outflanknl/Presentations/blob/master/HackInParis2019_WhoWatchesTheWatchmen_Bergman-Smeetsfinal.pdf)
- x33fcon 2019 Catching Blue Team OPSEC failures [video](https://www.youtube.com/watch?v=-CNMgh0yJag) and [slides](https://github.com/outflanknl/Presentations/blob/master/x33fcon2019_OutOfTheBlue-CatchingBlueTeamOPSECFailures_publicversion.pdf)
- BruCon 2018: Using Blue Team techniques in Red Team ops [video](https://www.youtube.com/watch?v=OjtftdPts4g) and [slides](https://github.com/outflanknl/Presentations/blob/master/MirrorOnTheWall_BruCon2018_UsingBlueTeamTechniquesinRedTeamOps_Bergman-Smeets_FINAL.pdf)

# Quick Start

## Prerequisites

- **OS**: Ubuntu 22.04 LTS or Debian 12
- **RAM**: 4GB minimum (8GB+ recommended)
- **Disk**: 20GB+ free space
- **Docker**: 20.10+ with Docker Compose v2
- **Root access** required

## Installation (v3.0 Modern Method)

### Option 1: Package Installation (Easiest)
```bash
# Download .deb package from GitHub Releases
wget https://github.com/volume19/RedELK/releases/download/v3.0.0/redelk_3.0.0_all.deb

# Install package
sudo dpkg -i redelk_3.0.0_all.deb
sudo apt-get install -f  # Fix dependencies if needed

# Run installer
sudo redelk-install --quickstart
```

**Done!** Access Kibana at `https://YOUR_SERVER_IP/`

### Option 2: Snap Package (Universal)
```bash
# Install from Snap Store (when published)
sudo snap install redelk --classic

# Run installer
sudo redelk.install --quickstart
```

### Option 3: Git Clone (For Development)
```bash
# Clone repository
git clone https://github.com/volume19/RedELK.git
cd RedELK

# Run quick installer (uses smart defaults)
sudo python3 install.py --quickstart
```

**Done!** Access Kibana at `https://YOUR_SERVER_IP/`

For detailed installation instructions, see **[INSTALL.md](INSTALL.md)**

## Post-Installation

```bash
# View service status
./redelk status

# View passwords
./redelk passwords

# View access URLs
./redelk urls

# Follow logs
./redelk logs --follow
```

## Deploy Agents to C2 Servers / Redirectors

```bash
# On the RedELK server, package agent configs
tar czf c2servers.tgz c2servers/
tar czf redirs.tgz redirs/

# Copy to your C2 server or redirector
scp c2servers.tgz root@c2server:/tmp/

# On the C2 server/redirector, run the unified installer
cd /tmp && tar xzf c2servers.tgz
cd c2servers
sudo python3 install-agent.py
```

## Management Commands

```bash
# Service management
make status          # Check status
make logs           # View logs
make restart        # Restart services
make stop           # Stop services
make start          # Start services

# Information
make passwords      # Show credentials
make urls          # Show access URLs
make info          # System info

# Maintenance
make backup         # Backup data
make update         # Update RedELK
make clean          # Clean temporary files
```

## Documentation

- **[Quick Start Guide](docs/QUICKSTART.md)** - Get up and running in 5 minutes
- **[Architecture](docs/ARCHITECTURE.md)** - Technical architecture and components
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Wiki](https://github.com/outflanknl/RedELK/wiki)** - Comprehensive documentation

## Alternative Installation Methods

### Legacy Installation (v2.x)
Check the [wiki](https://github.com/outflanknl/RedELK/wiki) for manual installation guide.

### Ansible Playbooks
- [RedELK Server playbook](https://github.com/fastlorenzo/redelk-server) - maintained by one of RedELK's developers
- [RedELK Client playbook](https://github.com/fastlorenzo/redelk-client) - maintained by one of RedELK's developers
- [ansible-redelk](https://github.com/curi0usJack/ansible-redelk) - maintained by curi0usJack/TrustedSec

# Conceptual overview #

Here's a conceptual overview of how RedELK works.

![](./images/redelk_overview.jpg)


# Authors and contribution #
This project is developed and maintained by:
- Marc Smeets (@MarcOverIP on [Github](https://github.com/MarcOverIP) and [Twitter](https://twitter.com/MarcOverIP))
- Mark Bergman (@xychix on [Github](https://github.com/xychix) and [Twitter](https://twitter.com/xychix))
- Lorenzo Bernardi (@fastlorenzo on [Github](https://github.com/fastlorenzo) and [Twitter](https://twitter.com/fastlorenzo))

We welcome contributions! Contributions can be both in code, as well as in ideas you might have for further development, alarms, usability improvements, etc.
