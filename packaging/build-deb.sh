#!/bin/bash
# Build RedELK .deb package for Ubuntu/Debian

set -e

VERSION="3.0.0"
PACKAGE_NAME="redelk_${VERSION}_all"
BUILD_DIR="$(pwd)/packaging/build"
DEB_ROOT="${BUILD_DIR}/${PACKAGE_NAME}"

echo "=================================="
echo "Building RedELK ${VERSION} .deb package"
echo "=================================="

# Clean previous builds
echo "[1/8] Cleaning previous builds..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Create package directory structure
echo "[2/8] Creating package structure..."
mkdir -p "${DEB_ROOT}/DEBIAN"
mkdir -p "${DEB_ROOT}/usr/bin"
mkdir -p "${DEB_ROOT}/usr/share/redelk"
mkdir -p "${DEB_ROOT}/usr/share/doc/redelk"
mkdir -p "${DEB_ROOT}/usr/share/man/man1"
mkdir -p "${DEB_ROOT}/opt/redelk"
mkdir -p "${DEB_ROOT}/etc/redelk"

# Copy DEBIAN control files
echo "[3/8] Copying control files..."
cp packaging/debian/DEBIAN/control "${DEB_ROOT}/DEBIAN/"
cp packaging/debian/DEBIAN/postinst "${DEB_ROOT}/DEBIAN/"
cp packaging/debian/DEBIAN/prerm "${DEB_ROOT}/DEBIAN/"
cp packaging/debian/DEBIAN/postrm "${DEB_ROOT}/DEBIAN/"
chmod 755 "${DEB_ROOT}/DEBIAN/postinst"
chmod 755 "${DEB_ROOT}/DEBIAN/prerm"
chmod 755 "${DEB_ROOT}/DEBIAN/postrm"

# Copy main scripts to /usr/bin
echo "[4/8] Installing executables..."
cp install.py "${DEB_ROOT}/usr/bin/redelk-install"
cp install-agent.py "${DEB_ROOT}/usr/bin/redelk-install-agent"
cp redelk "${DEB_ROOT}/usr/bin/redelk"
chmod 755 "${DEB_ROOT}/usr/bin/"*

# Copy support files to /usr/share/redelk
echo "[5/8] Installing application files..."
cp -r scripts "${DEB_ROOT}/usr/share/redelk/"
cp -r c2servers "${DEB_ROOT}/usr/share/redelk/"
cp -r redirs "${DEB_ROOT}/usr/share/redelk/"
cp -r elkserver "${DEB_ROOT}/usr/share/redelk/"
cp -r certs "${DEB_ROOT}/usr/share/redelk/"
cp -r example-data-and-configs "${DEB_ROOT}/usr/share/redelk/"
cp -r helper-scripts "${DEB_ROOT}/usr/share/redelk/"
cp Makefile "${DEB_ROOT}/usr/share/redelk/"
cp env.template "${DEB_ROOT}/usr/share/redelk/"
cp VERSION "${DEB_ROOT}/usr/share/redelk/"
cp LICENSE "${DEB_ROOT}/usr/share/redelk/"

# Copy documentation
echo "[6/8] Installing documentation..."
cp README.md "${DEB_ROOT}/usr/share/doc/redelk/"
cp README_v3.md "${DEB_ROOT}/usr/share/doc/redelk/"
cp CHANGELOG.md "${DEB_ROOT}/usr/share/doc/redelk/"
cp PROJECT_STRUCTURE.md "${DEB_ROOT}/usr/share/doc/redelk/"
cp CLEANUP_SUMMARY.md "${DEB_ROOT}/usr/share/doc/redelk/"
cp -r docs "${DEB_ROOT}/usr/share/doc/redelk/"

# Create working directory structure
echo "[7/8] Creating working directories..."
mkdir -p "${DEB_ROOT}/opt/redelk"

# Build the package
echo "[8/8] Building .deb package..."
dpkg-deb --build "${DEB_ROOT}"

# Move to current directory
mv "${BUILD_DIR}/${PACKAGE_NAME}.deb" "./"

echo ""
echo "=================================="
echo "✅ Package built successfully!"
echo "=================================="
echo ""
echo "Package: ${PACKAGE_NAME}.deb"
echo "Size: $(du -h ${PACKAGE_NAME}.deb | cut -f1)"
echo ""
echo "Install with:"
echo "  sudo dpkg -i ${PACKAGE_NAME}.deb"
echo "  sudo apt-get install -f  # Fix dependencies if needed"
echo ""
echo "Or upload to a repository for apt install."
echo ""

