#!/bin/bash
#
# Create a deployment package for RedELK v3.0
# This packages everything needed for Ubuntu deployment
#

echo "Creating RedELK v3.0 deployment package..."

# Package name with date
PACKAGE="redelk_v3_deployment_$(date +%Y%m%d).tar.gz"

# Create the package
tar czf "$PACKAGE" \
    redelk_ubuntu_deploy.sh \
    ubuntu_preflight.sh \
    README.md \
    LICENSE \
    VERSION \
    elkserver/ \
    c2servers/ \
    redirs/ \
    certs/config.cnf.example \
    helper-scripts/ \
    scripts/ \
    --exclude="*.pyc" \
    --exclude="__pycache__" \
    --exclude=".git" \
    --exclude=".gitignore" \
    --exclude=".dockerignore"

echo "✅ Deployment package created: $PACKAGE"
echo ""
echo "To deploy on Ubuntu server:"
echo "  1. Copy to server: scp $PACKAGE root@SERVER_IP:/tmp/"
echo "  2. Extract: tar xzf /tmp/$PACKAGE"
echo "  3. Deploy: bash redelk_ubuntu_deploy.sh"
echo ""
echo "Package size: $(du -h $PACKAGE | cut -f1)"