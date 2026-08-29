!/usr/bin/env bash
# Shared configuration for the GB300 4-VM GPU-passthrough scripts.
# Source this from every other script:  source "$(dirname "$0")/vars.sh"
set -euo pipefail

# --- Paths ---------------------------------------------------------------
VMS_HOME="${HOME}/vms"
XML_DIR="${VMS_HOME}/xml"
SCRIPTS_DIR="${VMS_HOME}/scripts"
DOCS_DIR="${VMS_HOME}/docs"

DATA_DIR="/data/vms"
IMAGES_DIR="${DATA_DIR}/images"
SEEDS_DIR="${DATA_DIR}/seeds"

BASE_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"
BASE_IMAGE="${IMAGES_DIR}/noble-server-cloudimg-arm64.img"

STORAGE_POOL_NAME="vms-data"

AAVMF_CODE="/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd"
AAVMF_VARS_TEMPLATE="/usr/share/AAVMF/AAVMF_VARS.fd"

# Override with: SSH_PUBKEY_PATH=/path/to/key.pub ./02-make-seed.sh ...
SSH_PUBKEY_PATH="${SSH_PUBKEY_PATH:-${HOME}/.ssh/id_ed25519.pub}"

DISK_SIZE_GIB=150
HUGEPAGES_PER_NODE=128   # 128 x 1G = 128 GiB reserved per host NUMA node (0 and 1)

# --- Per-VM assignment table (see plan for derivation) --------------------
VM_NAMES=(vm-gpu0 vm-gpu1 vm-gpu2 vm-gpu3)

declare -A VM_GPU=(
  [vm-gpu0]="0008:06:00.0"
  [vm-gpu1]="0009:06:00.0"
  [vm-gpu2]="0018:06:00.0"
  [vm-gpu3]="0019:06:00.0"
)
declare -A VM_CPUSET=(
  [vm-gpu0]="4-37"
  [vm-gpu1]="38-71"
  [vm-gpu2]="76-109"
  [vm-gpu3]="110-143"
)
declare -A VM_NUMA=(
  [vm-gpu0]=0
  [vm-gpu1]=0
  [vm-gpu2]=1
  [vm-gpu3]=1
)
declare -A VM_MEMORY_GIB=(
  [vm-gpu0]=128
  [vm-gpu1]=128
  [vm-gpu2]=128
  [vm-gpu3]=128
)

# "0008:06:00.0" -> prints: 0x0008 0x06 0x00 0x0
pci_addr_to_libvirt() {
  local addr="$1" domain rest bus slot func
  domain="${addr%%:*}"; rest="${addr#*:}"
  bus="${rest%%:*}"; rest="${rest#*:}"
  slot="${rest%%.*}"; func="${rest#*.}"
  echo "0x${domain} 0x${bus} 0x${slot} 0x${func}"
}
