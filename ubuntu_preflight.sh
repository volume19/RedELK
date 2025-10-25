#!/bin/bash
#
# RedELK Ubuntu Pre-flight Check
# Run this first to verify your Ubuntu server is ready
#

echo "================================================"
echo "     RedELK Ubuntu Server Pre-flight Check     "
echo "================================================"
echo ""

# Check Ubuntu version
echo "✓ Checking Ubuntu version..."
if command -v lsb_release &> /dev/null; then
    VERSION=$(lsb_release -rs)
    DISTRO=$(lsb_release -is)
    echo "  OS: $DISTRO $VERSION"
    if [[ "$DISTRO" == "Ubuntu" ]] && [[ "$VERSION" =~ ^(20\.04|22\.04|24\.04)$ ]]; then
        echo "  ✅ Ubuntu version supported"
    else
        echo "  ❌ Unsupported version (need Ubuntu 20.04/22.04/24.04)"
    fi
else
    echo "  ❌ Not Ubuntu or lsb_release not found"
fi
echo ""

# Check if root
echo "✓ Checking privileges..."
if [[ $EUID -eq 0 ]]; then
    echo "  ✅ Running as root"
else
    echo "  ⚠️  Not running as root (will need sudo)"
fi
echo ""

# Check system resources
echo "✓ Checking system resources..."
CPU_CORES=$(nproc)
MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

echo "  CPU Cores: $CPU_CORES (minimum: 4)"
echo "  Memory: ${MEMORY_GB}GB (minimum: 8GB)"
echo "  Disk Space: ${DISK_GB}GB available (minimum: 20GB)"

if [[ $CPU_CORES -ge 4 ]] && [[ $MEMORY_GB -ge 7 ]] && [[ $DISK_GB -ge 20 ]]; then
    echo "  ✅ System resources adequate"
else
    echo "  ⚠️  System resources may be insufficient"
fi
echo ""

# Check network
echo "✓ Checking network..."
if ping -c 1 google.com &> /dev/null; then
    echo "  ✅ Internet connection working"
else
    echo "  ❌ No internet connection"
fi

# Get IP address
IP=$(ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
echo "  Server IP: $IP"
echo ""

# Check if Docker is installed
echo "✓ Checking existing installations..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    echo "  ⚠️  Docker already installed: $DOCKER_VERSION"
    echo "     (Script will use existing installation)"
else
    echo "  ✅ Docker not installed (will be installed)"
fi

if command -v docker-compose &> /dev/null; then
    DC_VERSION=$(docker-compose --version | awk '{print $3}' | sed 's/,//')
    echo "  ⚠️  Docker Compose already installed: $DC_VERSION"
else
    echo "  ✅ Docker Compose not installed (will be installed)"
fi
echo ""

# Check ports
echo "✓ Checking port availability..."
PORTS=(443 5044 80)
PORTS_OK=true

for PORT in "${PORTS[@]}"; do
    if netstat -tln | grep -q ":$PORT "; then
        echo "  ⚠️  Port $PORT is already in use"
        PORTS_OK=false
    else
        echo "  ✅ Port $PORT is available"
    fi
done
echo ""

# Final verdict
echo "================================================"
echo "                   SUMMARY                     "
echo "================================================"

if [[ "$DISTRO" == "Ubuntu" ]] && [[ "$VERSION" =~ ^(20\.04|22\.04|24\.04)$ ]] && \
   [[ $CPU_CORES -ge 4 ]] && [[ $MEMORY_GB -ge 7 ]] && [[ $DISK_GB -ge 20 ]] && \
   $PORTS_OK && ping -c 1 google.com &> /dev/null; then
    echo ""
    echo "  ✅ SYSTEM READY FOR REDELK DEPLOYMENT!"
    echo ""
    echo "  Next step: Run the deployment script:"
    echo "  bash redelk_ubuntu_deploy.sh"
else
    echo ""
    echo "  ⚠️  SYSTEM NEEDS ATTENTION"
    echo ""
    echo "  Please resolve any ❌ or ⚠️ issues above"
    echo "  before running the deployment script."
fi
echo ""
echo "================================================"