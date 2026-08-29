#!/usr/bin/env bash
# Stage 1c: create a thin-provisioned qcow2 overlay disk for a VM, backed by
# the shared base cloud image.
# Usage: ./03-make-disk.sh <vm-name>
set -euo pipefail
source "$(dirname "$0")/vars.sh"

vm="${1:?usage: $0 <vm-name>}"
: "${VM_GPU[$vm]:?unknown vm: $vm}"
[[ -f "${BASE_IMAGE}" ]] || { echo "base image missing, run 01-fetch-base-image.sh first" >&2; exit 1; }

disk="${IMAGES_DIR}/${vm}.qcow2"
if [[ -f "${disk}" ]]; then
  echo "disk already exists: ${disk}"
else
  qemu-img create -f qcow2 -F qcow2 -b "${BASE_IMAGE}" "${disk}" "${DISK_SIZE_GIB}G"
  echo "created ${disk}"
fi
qemu-img info "${disk}"
