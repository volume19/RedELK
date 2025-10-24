# RedELK Packaging Guide

Complete guide for building and distributing RedELK packages.

## 🎯 Overview

RedELK v3.0 supports multiple packaging formats for easy distribution:

1. **.deb Package** - For Ubuntu/Debian systems (apt/dpkg)
2. **Snap Package** - Universal Linux package with auto-updates
3. **Source Tarball** - Traditional source distribution

## 🏗️ Building Packages

### Prerequisites

```bash
# For .deb packages
sudo apt-get install dpkg-dev build-essential

# For snap packages
sudo snap install snapcraft --classic

# For both
sudo apt-get install git
```

### Build All Packages

**Easiest method:**
```bash
cd RedELK
chmod +x packaging/build-all.sh
./packaging/build-all.sh
```

This creates:
- `packages/redelk_3.0.0_all.deb`
- `packages/redelk_3.0.0_amd64.snap`
- `packages/redelk-3.0.0.tar.gz`
- `packages/SHA256SUMS`

### Build Individual Packages

#### .deb Package
```bash
chmod +x packaging/build-deb.sh
./packaging/build-deb.sh
```

#### Snap Package
```bash
cd packaging
snapcraft
```

#### Source Tarball
```bash
tar czf redelk-3.0.0.tar.gz \
  --exclude='.git' \
  --exclude='*.pyc' \
  --exclude='__pycache__' \
  .
```

## 📦 Package Details

### .deb Package

**File**: `redelk_3.0.0_all.deb`  
**Size**: ~50MB  
**Format**: Debian binary package

**Contents:**
- Executables in `/usr/bin/`
  - `redelk` - Management CLI
  - `redelk-install` - Main installer
  - `redelk-install-agent` - Agent installer
  
- Application files in `/usr/share/redelk/`
  - All scripts and configs
  - Docker files
  - Examples
  
- Documentation in `/usr/share/doc/redelk/`
  - QUICKSTART.md
  - ARCHITECTURE.md
  - TROUBLESHOOTING.md
  
- Working directory: `/opt/redelk/`
- Configuration: `/etc/redelk/`
- Logs: `/var/log/redelk/`

**Install:**
```bash
sudo dpkg -i redelk_3.0.0_all.deb
sudo apt-get install -f  # Install dependencies
```

**Usage:**
```bash
redelk-install --quickstart
redelk status
```

### Snap Package

**File**: `redelk_3.0.0_amd64.snap`  
**Size**: ~60MB  
**Format**: Snap package (Squashfs)

**Contents:**
- Self-contained application
- Python runtime included
- All dependencies bundled

**Install:**
```bash
sudo snap install redelk --classic
```

**Usage:**
```bash
redelk.install --quickstart
redelk.status
```

**Auto-updates:** Yes (from Snap Store)

### Source Tarball

**File**: `redelk-3.0.0.tar.gz`  
**Size**: ~50MB  
**Format**: Compressed archive

**Contents:**
- All source files
- Documentation
- Scripts

**Install:**
```bash
tar xzf redelk-3.0.0.tar.gz
cd RedELK
sudo python3 install.py --quickstart
```

## 🚀 Distribution

### GitHub Releases (Recommended)

1. **Create Release on GitHub:**
   ```bash
   # Tag the release
   git tag -a v3.0.0 -m "RedELK v3.0.0"
   git push origin v3.0.0
   ```

2. **Upload Packages:**
   - Go to: https://github.com/volume19/RedELK/releases
   - Click "Draft a new release"
   - Choose tag: v3.0.0
   - Upload:
     - `redelk_3.0.0_all.deb`
     - `redelk_3.0.0_amd64.snap`
     - `redelk-3.0.0.tar.gz`
     - `SHA256SUMS`

3. **Release Notes:**
   Copy content from `CHANGELOG.md` and `README_v3.md`

### Snap Store (Official Distribution)

1. **Create Snap Store Account:**
   - Visit: https://snapcraft.io/
   - Create developer account

2. **Login:**
   ```bash
   snapcraft login
   ```

3. **Upload Snap:**
   ```bash
   snapcraft upload redelk_3.0.0_amd64.snap
   ```

4. **Release to Channel:**
   ```bash
   snapcraft release redelk 3.0.0 stable
   ```

5. **Users Install:**
   ```bash
   sudo snap install redelk
   ```

### PPA (Ubuntu Package Repository)

1. **Create Launchpad Account:**
   - Visit: https://launchpad.net/

2. **Create PPA:**
   - Click "Create a new PPA"
   - Name: redelk
   - Description: Red Team SIEM

3. **Build Source Package:**
   ```bash
   cd RedELK
   debuild -S -sa
   ```

4. **Upload to PPA:**
   ```bash
   dput ppa:yourusername/redelk redelk_3.0.0_source.changes
   ```

5. **Users Install:**
   ```bash
   sudo add-apt-repository ppa:yourusername/redelk
   sudo apt-get update
   sudo apt-get install redelk
   ```

## 🔐 Package Signing

### Sign .deb Package

```bash
# Install signing tools
sudo apt-get install dpkg-sig

# Generate GPG key (if needed)
gpg --gen-key

# Sign package
dpkg-sig --sign builder redelk_3.0.0_all.deb

# Verify signature
dpkg-sig --verify redelk_3.0.0_all.deb

# Users verify
dpkg-sig --verify redelk_3.0.0_all.deb
```

### Create SHA256 Checksums

```bash
cd packages
sha256sum * > SHA256SUMS

# Sign checksums
gpg --clearsign SHA256SUMS
```

### Users Verify

```bash
# Verify checksum
sha256sum -c SHA256SUMS

# Verify GPG signature
gpg --verify SHA256SUMS.asc
```

## 🧪 Testing Packages

### Test .deb in Docker

```bash
# Create test container
docker run -it --privileged --name redelk-test ubuntu:22.04 bash

# Inside container
apt-get update
apt-get install -y ./redelk_3.0.0_all.deb

# Verify
redelk --version
which redelk-install

# Test installation
redelk-install --help

# Cleanup
exit
docker rm redelk-test
```

### Test Snap in Multipass

```bash
# Create VM
multipass launch --name redelk-snap-test 22.04

# Shell into VM
multipass shell redelk-snap-test

# Install snap
sudo snap install redelk_3.0.0_amd64.snap --classic --dangerous

# Verify
redelk --version

# Cleanup
exit
multipass delete redelk-snap-test
multipass purge
```

### Test in Real VM

Use VirtualBox, VMware, or cloud VM:
```bash
# Create Ubuntu 22.04 VM
# Download package
# Install and test
```

## 📊 Package Comparison

| Feature | .deb | Snap | Tarball |
|---------|------|------|---------|
| **Size** | ~50MB | ~60MB | ~50MB |
| **Dependencies** | System packages | Bundled | Manual |
| **Auto-updates** | No | Yes | No |
| **System integration** | Full | Sandboxed | None |
| **Ease of install** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Universal** | Debian/Ubuntu | All Linux | All Linux |

## 🎯 Recommended Distribution Strategy

### For Most Users
1. **Primary**: Publish .deb to GitHub Releases
2. **Secondary**: Publish snap to Snap Store
3. **Fallback**: Provide git clone instructions

### For Enterprise
1. Host .deb in private repository
2. Sign all packages
3. Provide SHA256 checksums

### For Developers
1. Git clone method
2. Source tarball on GitHub

## 📝 Package Maintenance

### Updating Packages

When releasing new version (e.g., 3.1.0):

1. **Update version in:**
   - `VERSION` file
   - `packaging/debian/DEBIAN/control`
   - `packaging/snapcraft.yaml`
   - All Python scripts

2. **Rebuild packages:**
   ```bash
   ./packaging/build-all.sh
   ```

3. **Test packages:**
   ```bash
   # Test .deb
   docker run -it ubuntu:22.04 bash
   # Test snap
   multipass launch 22.04
   ```

4. **Upload to GitHub Releases**

5. **Update Snap Store** (if applicable)

### Changelog

Always update `CHANGELOG.md` with:
- Version number
- Release date
- New features
- Bug fixes
- Breaking changes

## 🐛 Troubleshooting Package Builds

### .deb Build Fails

**Issue**: Permission errors
```bash
# Fix permissions
chmod +x packaging/build-deb.sh
chmod 755 packaging/debian/DEBIAN/postinst
chmod 755 packaging/debian/DEBIAN/prerm
chmod 755 packaging/debian/DEBIAN/postrm
```

**Issue**: dpkg-deb not found
```bash
sudo apt-get install dpkg-dev
```

### Snap Build Fails

**Issue**: snapcraft not installed
```bash
sudo snap install snapcraft --classic
```

**Issue**: LXD not set up
```bash
sudo snap install lxd
sudo lxd init --auto
```

**Issue**: Build fails
```bash
# Clean and retry
snapcraft clean
snapcraft --debug
```

## 📚 Additional Resources

- **Debian Packaging Guide**: https://www.debian.org/doc/manuals/maint-guide/
- **Snap Documentation**: https://snapcraft.io/docs
- **Ubuntu Packaging**: https://packaging.ubuntu.com/

## ✅ Checklist for Release

Before releasing packages:

- [ ] Version bumped in all files
- [ ] CHANGELOG.md updated
- [ ] All tests passing
- [ ] Packages built successfully
- [ ] Packages tested in clean environment
- [ ] SHA256 checksums generated
- [ ] Packages signed (optional but recommended)
- [ ] Documentation updated
- [ ] GitHub release drafted
- [ ] Release notes written

---

**Version**: 3.0.0  
**Last Updated**: October 2024  
**Maintainer**: RedELK Team

