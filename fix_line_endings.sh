#!/bin/bash
# Fix line endings for Unix/Linux systems
# Run this before transferring to Ubuntu

for file in *.sh; do
    if [ -f "$file" ]; then
        echo "Fixing line endings for $file..."
        sed -i 's/\r$//' "$file"
    fi
done

echo "Line endings fixed for all .sh files"