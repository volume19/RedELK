#!/bin/bash
# Build all RedELK packages

set -e

VERSION="3.0.0"

echo "========================================"
echo "Building All RedELK v${VERSION} Packages"
echo "========================================"
echo ""

# Check if we're in the right directory
if [ ! -f "VERSION" ]; then
    echo "❌ Error: Must run from RedELK root directory"
    exit 1
fi

# Create packages directory
mkdir -p packages

echo "📦 Package Build Pipeline"
echo ""

# 1. Build .deb package
if command -v dpkg-deb &> /dev/null; then
    echo "[1/4] Building .deb package..."
    chmod +x packaging/build-deb.sh
    bash packaging/build-deb.sh
    
    if [ -f "redelk_${VERSION}_all.deb" ]; then
        mv "redelk_${VERSION}_all.deb" packages/
        echo "✅ .deb package: packages/redelk_${VERSION}_all.deb"
    else
        echo "⚠️  .deb build failed or skipped"
    fi
else
    echo "[1/4] ⚠️  dpkg-deb not found, skipping .deb build"
fi
echo ""

# 2. Build snap package
if command -v snapcraft &> /dev/null; then
    echo "[2/4] Building snap package..."
    cd packaging
    snapcraft clean
    snapcraft
    cd ..
    
    if [ -f "packaging/redelk_${VERSION}_amd64.snap" ]; then
        mv "packaging/redelk_${VERSION}_amd64.snap" packages/
        echo "✅ Snap package: packages/redelk_${VERSION}_amd64.snap"
    else
        echo "⚠️  Snap build failed or skipped"
    fi
else
    echo "[2/4] ⚠️  snapcraft not found, skipping snap build"
fi
echo ""

# 3. Create tarball (universal)
echo "[3/4] Creating source tarball..."
tar czf "packages/redelk-${VERSION}.tar.gz" \
    --exclude='.git' \
    --exclude='packaging/build' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.log' \
    --exclude='*.tgz' \
    --exclude='certs/*.crt' \
    --exclude='certs/*.key' \
    .

if [ -f "packages/redelk-${VERSION}.tar.gz" ]; then
    echo "✅ Tarball: packages/redelk-${VERSION}.tar.gz"
else
    echo "❌ Tarball build failed"
fi
echo ""

# 4. Create checksums
echo "[4/4] Generating checksums..."
cd packages
sha256sum * > SHA256SUMS 2>/dev/null || shasum -a 256 * > SHA256SUMS
cd ..
echo "✅ Checksums: packages/SHA256SUMS"
echo ""

# Summary
echo "========================================"
echo "✅ Build Complete!"
echo "========================================"
echo ""
echo "Packages created in ./packages/:"
ls -lh packages/ 2>/dev/null
echo ""
echo "Next steps:"
echo "1. Test packages in clean VM/container"
echo "2. Sign packages (optional but recommended)"
echo "3. Upload to GitHub Releases"
echo "4. Publish to Snap Store (if snap built)"
echo "5. Create PPA (optional)"
echo ""
echo "Quick test:"
echo "  docker run -it --privileged ubuntu:22.04 bash"
echo "  apt update && apt install ./redelk_${VERSION}_all.deb"
echo ""

