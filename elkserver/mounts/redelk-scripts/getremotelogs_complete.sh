#!/bin/bash
#
# Part of RedELK
# Script to sync C2 server artifacts to the RedELK server
#
# This script runs via cron to pull logs, screenshots, keystrokes, and downloads
# from C2 servers and make them available through the RedELK interface
#
# Author: Outflank B.V. / Marc Smeets
#

# Configuration
LOGFILE="/var/log/redelk/getremotelogs.log"
RSYNC_TIMEOUT=120
THUMBSIZE="200x200"
WEBROOT="/usr/share/nginx/html"
CSLOGSDIR="${WEBROOT}/cslogs"

# Ensure log directory exists
mkdir -p $(dirname $LOGFILE)

# Function to log messages
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> $LOGFILE
}

# Validate arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <c2host> <scpuser>"
    log_message "ERROR: Invalid arguments provided"
    exit 1
fi

C2HOST=$1
SCPUSER=$2

log_message "INFO: Starting sync from $C2HOST as user $SCPUSER"

# Ensure destination directories exist
mkdir -p ${CSLOGSDIR}/${C2HOST}
mkdir -p ${CSLOGSDIR}/${C2HOST}/screenshots
mkdir -p ${CSLOGSDIR}/${C2HOST}/keystrokes
mkdir -p ${CSLOGSDIR}/${C2HOST}/downloads
mkdir -p ${CSLOGSDIR}/${C2HOST}/beaconlogs

# Function to sync directory
sync_directory() {
    local SRC=$1
    local DST=$2
    local DESC=$3

    log_message "INFO: Syncing $DESC from $C2HOST"

    rsync -avz \
        --timeout=${RSYNC_TIMEOUT} \
        --delete \
        --exclude="*.tmp" \
        --exclude="*.lock" \
        -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=30" \
        ${SCPUSER}@${C2HOST}:${SRC} \
        ${DST} >> $LOGFILE 2>&1

    if [ $? -eq 0 ]; then
        log_message "INFO: Successfully synced $DESC"
        return 0
    else
        log_message "ERROR: Failed to sync $DESC"
        return 1
    fi
}

# Sync Cobalt Strike logs (if exists)
if ssh -o BatchMode=yes -o ConnectTimeout=5 ${SCPUSER}@${C2HOST} "test -d /root/cobaltstrike/server/logs" 2>/dev/null; then
    log_message "INFO: Detected Cobalt Strike on $C2HOST"

    # Sync main logs directory
    sync_directory "/root/cobaltstrike/server/logs/" "${CSLOGSDIR}/${C2HOST}/cslogs/" "Cobalt Strike logs"

    # Process screenshots
    log_message "INFO: Processing screenshots for thumbnails"
    find ${CSLOGSDIR}/${C2HOST}/cslogs/ -name "screenshot_*.jpg" -type f | while read IMG; do
        THUMB="${IMG}.thumb.jpg"
        if [ ! -f "$THUMB" ] || [ "$IMG" -nt "$THUMB" ]; then
            convert "$IMG" -thumbnail ${THUMBSIZE} "$THUMB" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "DEBUG: Created thumbnail for $(basename $IMG)"
            fi
        fi
    done

    # Create symlinks for easy access
    ln -sfn ${CSLOGSDIR}/${C2HOST}/cslogs/*/screenshots ${CSLOGSDIR}/${C2HOST}/screenshots/
    ln -sfn ${CSLOGSDIR}/${C2HOST}/cslogs/*/keystrokes ${CSLOGSDIR}/${C2HOST}/keystrokes/
    ln -sfn ${CSLOGSDIR}/${C2HOST}/cslogs/*/downloads ${CSLOGSDIR}/${C2HOST}/downloads/

    # Copy beacon logs for easy access
    find ${CSLOGSDIR}/${C2HOST}/cslogs/ -name "beacon_*.log" -type f -exec cp {} ${CSLOGSDIR}/${C2HOST}/beaconlogs/ \; 2>/dev/null
fi

# Sync Sliver logs (if exists)
if ssh -o BatchMode=yes -o ConnectTimeout=5 ${SCPUSER}@${C2HOST} "test -d /root/.sliver/logs" 2>/dev/null; then
    log_message "INFO: Detected Sliver on $C2HOST"
    sync_directory "/root/.sliver/logs/" "${CSLOGSDIR}/${C2HOST}/sliver/" "Sliver logs"
fi

# Sync PoshC2 logs (if exists)
if ssh -o BatchMode=yes -o ConnectTimeout=5 ${SCPUSER}@${C2HOST} "test -d /opt/PoshC2/reports" 2>/dev/null; then
    log_message "INFO: Detected PoshC2 on $C2HOST"
    sync_directory "/opt/PoshC2/reports/" "${CSLOGSDIR}/${C2HOST}/poshc2/" "PoshC2 logs"
fi

# Set proper permissions
chown -R www-data:www-data ${CSLOGSDIR}/${C2HOST}/
chmod -R 755 ${CSLOGSDIR}/${C2HOST}/

# Update index file for web browsing
cat > ${CSLOGSDIR}/${C2HOST}/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>C2 Logs - ${C2HOST}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .section { margin: 20px 0; padding: 10px; border: 1px solid #ddd; }
        a { color: #0066cc; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>C2 Server Logs: ${C2HOST}</h1>
    <div class="section">
        <h2>Quick Links</h2>
        <ul>
            <li><a href="screenshots/">Screenshots</a></li>
            <li><a href="keystrokes/">Keystrokes</a></li>
            <li><a href="downloads/">Downloads</a></li>
            <li><a href="beaconlogs/">Beacon Logs</a></li>
            <li><a href="cslogs/">Raw CS Logs</a></li>
        </ul>
    </div>
    <div class="section">
        <p>Last Updated: $(date)</p>
    </div>
</body>
</html>
EOF

log_message "INFO: Completed sync for $C2HOST"

# Exit successfully
exit 0