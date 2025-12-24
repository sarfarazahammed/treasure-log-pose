#!/bin/bash
set -euxo pipefail

# Directory to save downloads
DOWNLOAD_DIR="/opt/flink/lib"

# Loop through arguments (URL and filename pairs)
while [ $# -gt 0 ]; do
    url="$1"
    filename="$2"
    
    # Download to specified directory
    curl -L -o "${DOWNLOAD_DIR}/${filename}" "${url}"

    # Immediately chown the downloaded file
    chown flink:flink "${DOWNLOAD_DIR}/${filename}"
    
    # Shift to next pair of arguments
    shift 2
done
