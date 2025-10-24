# RedELK Installation Guide

Multiple installation methods for RedELK v3.0.

## 🚀 Quick Install (Recommended)

### Option 1: Package Installation (.deb)

**Ubuntu/Debian users - easiest method!**

```bash
# Download package from GitHub Releases
wget https://github.com/volume19/RedELK/releases/download/v3.0.0/redelk_3.0.0_all.deb

# Install package
sudo dpkg -i redelk_3.0.0_all.deb
sudo apt-get install -f  # Fix dependencies if needed

# Run installer
sudo redelk-install --quickstart

# Done! Access at https://YOUR_SERVER/
```

### Option 2: Snap Package

**Universal Linux package with auto-updates:**

```bash
# Install from Snap Store (when published)
sudo snap install redelk --classic

# Or install local snap
sudo snap install redelk_3.0.0_amd64.snap --classic --dangerous

# Run installer
sudo redelk.install --quickstart

# Manage
redelk.status
redelk.logs
```

### Option 3: Git Clone (Traditional)

**For developers or if packages aren't available:**

```bash
# Clone repository
git clone https://github.com/volume19/RedELK.git
cd RedELK

# Run installer
sudo python3 install.py --quickstart

# Manage
./redelk status
make logs
```

## 📋 Prerequisites

All installation methods require:
- **OS**: Ubuntu 22.04 LTS or Debian 12
- **RAM**: 4GB minimum (8GB+ recommended)
- **Disk**: 20GB+ free space
- **Docker**: Version 20.10+
- **Root access**: Required

### Install Docker (if not installed)

```bash
# Install Docker
curl -fsSL https://get.docker.com | sudo sh

# Install Docker Compose plugin
sudo apt-get install docker-compose-plugin

# Verify installation
docker --version
docker compose version
```

## 🎯 Installation Methods Comparison

| Method | Ease | Speed | Updates | Best For |
|--------|------|-------|---------|----------|
| **.deb** | ⭐⭐⭐⭐⭐ | Fast | Manual | Ubuntu/Debian users |
| **Snap** | ⭐⭐⭐⭐ | Medium | Automatic | Universal Linux |
| **Git Clone** | ⭐⭐⭐ | Fast | Manual | Developers, customization |

## 📦 Detailed Installation Steps

### Method 1: .deb Package Installation

#### Step 1: Download Package
```bash
# From GitHub Releases
wget https://github.com/volume19/RedELK/releases/download/v3.0.0/redelk_3.0.0_all.deb

# Or build yourself
git clone https://github.com/volume19/RedELK.git
cd RedELK/packaging
chmod +x build-deb.sh
./build-deb.sh
```

#### Step 2: Install Package
```bash
sudo dpkg -i redelk_3.0.0_all.deb

# If dependency errors:
sudo apt-get install -f
```

#### Step 3: Verify Installation
```bash
# Check commands are available
which redelk
which redelk-install

# View version
redelk --version
```

#### Step 4: Run Installer
```bash
# Quick start (automated)
sudo redelk-install --quickstart

# Or interactive (guided)
sudo redelk-install
```

#### Step 5: Access RedELK
```bash
# View access info
redelk passwords
redelk urls

# Open browser to
# https://YOUR_SERVER_IP/
```

### Method 2: Snap Package Installation

#### Step 1: Install Snap
```bash
# Install snapd (if not installed)
sudo apt-get update
sudo apt-get install snapd
```

#### Step 2: Install RedELK Snap
```bash
# From Snap Store (when published)
sudo snap install redelk --classic

# Or from local file
sudo snap install redelk_3.0.0_amd64.snap --classic --dangerous
```

#### Step 3: Run Installer
```bash
sudo redelk.install --quickstart
```

#### Step 4: Manage Services
```bash
redelk.status
redelk.logs --follow
redelk.passwords
```

### Method 3: Git Clone Installation

#### Step 1: Clone Repository
```bash
git clone https://github.com/volume19/RedELK.git
cd RedELK
```

#### Step 2: Run Installer
```bash
# Quick start
sudo python3 install.py --quickstart

# Or interactive
sudo python3 install.py
```

#### Step 3: Manage
```bash
./redelk status
make logs
```

## 🔧 Post-Installation

### Verify Installation
```bash
# Check all services
redelk status
redelk health

# View logs
redelk logs --tail=100
```

### Configure RedELK
```bash
# View passwords
redelk passwords

# Edit configuration (optional)
nano /usr/share/redelk/elkserver/mounts/redelk-config/etc/redelk/config.json
```

### Deploy Agents
```bash
# On C2 servers and redirectors
sudo redelk-install-agent
```

## 🆘 Installation Troubleshooting

### "Docker not found"
```bash
# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl start docker
```

### "Permission denied"
```bash
# Run with sudo
sudo redelk-install
```

### "Port already in use"
```bash
# Check what's using ports
sudo netstat -tulpn | grep -E '(80|443|5044|9200)'

# Stop conflicting services
sudo systemctl stop apache2
sudo systemctl stop nginx
```

### Package dependency errors
```bash
# Fix broken dependencies
sudo apt-get install -f

# Update package lists
sudo apt-get update
```

## 🔄 Updating RedELK

### From Package (.deb)
```bash
# Download new version
wget https://github.com/volume19/RedELK/releases/download/v3.1.0/redelk_3.1.0_all.deb

# Install (upgrades existing)
sudo dpkg -i redelk_3.1.0_all.deb

# Restart services
redelk restart
```

### From Snap
```bash
# Manual update
sudo snap refresh redelk

# Auto-updates happen automatically
```

### From Git
```bash
cd RedELK
git pull origin master
sudo python3 install.py
```

## 🗑️ Uninstalling

### Remove .deb Package
```bash
# Remove package (keep config)
sudo apt-get remove redelk

# Remove package and config
sudo apt-get purge redelk

# Remove data (WARNING: deletes all RedELK data)
cd /usr/share/redelk/elkserver
docker-compose down -v
```

### Remove Snap
```bash
# Remove snap
sudo snap remove redelk

# Data is in /var/snap/redelk/
```

### Manual Removal
```bash
cd RedELK
make uninstall
```

## 📞 Getting Help

- **Documentation**: [docs/QUICKSTART.md](docs/QUICKSTART.md)
- **Troubleshooting**: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- **Issues**: https://github.com/volume19/RedELK/issues
- **Wiki**: https://github.com/outflanknl/RedELK/wiki

---

**Choose your method and get started in 5 minutes!** 🚀

