# RedELK Packaging

This directory contains files for creating Ubuntu/Debian packages for easy installation.

## 📦 Package Types

RedELK v3.0 can be packaged in multiple formats:

### 1. .deb Package (Debian/Ubuntu)
Traditional package format for Debian-based systems.

**Build:**
```bash
cd packaging
chmod +x build-deb.sh
./build-deb.sh
```

**Install:**
```bash
sudo dpkg -i redelk_3.0.0_all.deb
sudo apt-get install -f  # Fix dependencies if needed
```

**Usage:**
```bash
sudo redelk-install --quickstart
redelk status
```

### 2. Snap Package (Universal)
Modern containerized package for all Linux distributions.

**Build:**
```bash
cd packaging
snapcraft
```

**Install:**
```bash
sudo snap install redelk_3.0.0_amd64.snap --classic --dangerous
```

**Usage:**
```bash
sudo redelk.install --quickstart
redelk.status
```

### 3. Direct Installation (Current Method)
No package, just clone and run.

**Install:**
```bash
git clone https://github.com/outflanknl/RedELK.git
cd RedELK
sudo python3 install.py --quickstart
```

## 🏗️ Building Packages

### Prerequisites

#### For .deb packages:
```bash
sudo apt-get install dpkg-dev build-essential
```

#### For snap packages:
```bash
sudo snap install snapcraft --classic
```

### Build All Packages

```bash
# Build .deb
./packaging/build-deb.sh

# Build snap
cd packaging
snapcraft clean
snapcraft
```

## 📁 Package Structure

### .deb Package Layout
```
redelk_3.0.0_all.deb
├── DEBIAN/
│   ├── control        # Package metadata
│   ├── postinst       # Post-installation script
│   ├── prerm          # Pre-removal script
│   └── postrm         # Post-removal script
├── usr/
│   ├── bin/
│   │   ├── redelk-install
│   │   ├── redelk-install-agent
│   │   └── redelk
│   └── share/
│       ├── redelk/    # Application files
│       └── doc/redelk/ # Documentation
├── opt/redelk/        # Working directory
└── etc/redelk/        # Configuration
```

### Snap Package Layout
```
redelk_3.0.0_amd64.snap
├── usr/bin/
│   ├── redelk
│   ├── redelk-install
│   └── redelk-install-agent
└── usr/share/redelk/  # All application files
```

## 🎯 Usage After Installation

### From .deb Package
```bash
# Install
sudo dpkg -i redelk_3.0.0_all.deb

# Run installer
sudo redelk-install --quickstart

# Manage
redelk status
redelk logs
redelk passwords

# Install agents
sudo redelk-install-agent
```

### From Snap Package
```bash
# Install
sudo snap install redelk --classic

# Run installer
sudo redelk.install --quickstart

# Manage
redelk.status
redelk.logs
redelk.passwords

# Install agents
sudo redelk.install-agent
```

## 📝 Package Metadata

### Version
```
3.0.0
```

### Maintainer
```
RedELK Team <redelk@outflank.nl>
```

### Homepage
```
https://github.com/outflanknl/RedELK
```

### Dependencies (.deb)
- python3 (>= 3.8)
- python3-pip
- docker.io (>= 20.10) OR docker-ce (>= 20.10)
- docker-compose-plugin OR docker-compose (>= 2.0)

### Recommended
- curl
- wget
- openssl
- apache2-utils

## 🚀 Distribution

### Option 1: GitHub Releases
Upload .deb and .snap files to GitHub Releases:
```bash
# Tag the release
git tag -a v3.0.0 -m "RedELK v3.0.0"
git push origin v3.0.0

# Upload packages to GitHub Release page
```

### Option 2: PPA (Personal Package Archive)
For Ubuntu users to install via apt:
```bash
# Create PPA on Launchpad
# Upload source package
# Users can then:
sudo add-apt-repository ppa:yourusername/redelk
sudo apt-get update
sudo apt-get install redelk
```

### Option 3: Snap Store
Publish to official Snap Store:
```bash
snapcraft login
snapcraft upload redelk_3.0.0_amd64.snap
snapcraft release redelk 3.0.0 stable
```

Then users can:
```bash
sudo snap install redelk
```

### Option 4: Direct Download
Host on your own server:
```bash
# Users download
wget https://yourserver.com/packages/redelk_3.0.0_all.deb
sudo dpkg -i redelk_3.0.0_all.deb
```

## 📋 Installation Methods Comparison

| Method | Command | Pros | Cons |
|--------|---------|------|------|
| **.deb Package** | `dpkg -i redelk.deb` | Standard, dependencies | Manual download |
| **Snap** | `snap install redelk` | Auto-updates, universal | Larger size |
| **PPA/APT** | `apt install redelk` | Easiest, auto-updates | Need PPA setup |
| **Git Clone** | `git clone ...` | Latest code, flexible | Manual steps |

## 🔍 Testing Packages

### Test .deb Package
```bash
# Install in clean container
docker run -it --privileged ubuntu:22.04 bash
apt-get update
apt-get install -y ./redelk_3.0.0_all.deb

# Verify
redelk --version
which redelk-install
```

### Test Snap Package
```bash
# Install in clean VM
multipass launch --name redelk-test
multipass shell redelk-test
sudo snap install redelk_3.0.0_amd64.snap --classic --dangerous

# Verify
redelk --version
redelk.install --help
```

## 🐛 Troubleshooting

### .deb Build Fails
```bash
# Check dependencies
sudo apt-get install dpkg-dev

# Check permissions
chmod +x packaging/build-deb.sh

# Verbose build
bash -x packaging/build-deb.sh
```

### Snap Build Fails
```bash
# Clean and retry
snapcraft clean
snapcraft --debug

# Check snapcraft version
snapcraft --version
```

### Package Won't Install
```bash
# Check dependencies
sudo apt-get install -f

# View package info
dpkg -I redelk_3.0.0_all.deb

# View package contents
dpkg -c redelk_3.0.0_all.deb
```

## 📊 Package Sizes

**Estimated Sizes:**
- .deb package: ~50MB (without Docker images)
- Snap package: ~60MB (includes Python runtime)
- Docker images: ~2GB (downloaded during installation)

## 🎯 Recommended Approach

### For End Users
**Best:** Create PPA for `apt install redelk`
**Good:** Publish snap to Snap Store
**Okay:** Provide .deb on GitHub Releases

### For Testing
**Best:** .deb package (easy to build and test)
**Good:** Direct git clone method

### For Enterprise
**Best:** .deb package in private repository
**Good:** Download and verify signatures

## 📚 Additional Documentation

After package installation, documentation is available at:
- `/usr/share/doc/redelk/` - All documentation
- `/usr/share/doc/redelk/docs/QUICKSTART.md` - Quick start
- `redelk --help` - CLI help

## 🔐 Package Signing (Recommended)

### Sign .deb Package
```bash
# Generate GPG key if needed
gpg --gen-key

# Sign package
dpkg-sig --sign builder redelk_3.0.0_all.deb

# Verify signature
dpkg-sig --verify redelk_3.0.0_all.deb
```

### Sign Snap Package
```bash
# Snapcraft handles signing automatically when uploading
snapcraft upload redelk_3.0.0_amd64.snap
```

## 🚀 Next Steps

1. **Build packages**: Run build scripts
2. **Test packages**: Install in clean VM
3. **Sign packages**: Add GPG signatures
4. **Upload to GitHub**: Create release
5. **Publish to stores**: Snap Store, PPA
6. **Document**: Update installation docs
7. **Announce**: Share with community

---

**Version**: 3.0.0  
**Last Updated**: October 2024  
**Status**: Ready for packaging and distribution

