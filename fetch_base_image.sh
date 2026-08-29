#!/usr/bin/env bash
# Stage 1a: download the Ubuntu 24.04 arm64 cloud image once; every VM's disk
# is a thin qcow2 overlay backed by this file.
set -euo pipefail
source "$(dirname "$0")/vars.sh"

if [[ -f "${BASE_IMAGE}" ]]; then
  echo "Base image already present at ${BASE_IMAGE}"
else
  echo "Downloading ${BASE_IMAGE_URL} -> ${BASE_IMAGE}"
  curl -fL --progress-bar -o "${BASE_IMAGE}.tmp" "${BASE_IMAGE_URL}"
  mv "${BASE_IMAGE}.tmp" "${BASE_IMAGE}"
fi
qemu-img info "${BASE_IMAGE}"
