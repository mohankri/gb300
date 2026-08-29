#!/usr/bin/env bash
# Stage 1b: generate a per-VM cloud-init NoCloud seed ISO.
# Usage: ./02-make-seed.sh <vm-name>
set -euo pipefail
source "$(dirname "$0")/vars.sh"

vm="${1:?usage: $0 <vm-name>}"
: "${VM_GPU[$vm]:?unknown vm: $vm}"

if ! command -v cloud-localds >/dev/null 2>&1; then
  echo "installing cloud-image-utils (provides cloud-localds)"
  sudo apt-get update -y
  sudo apt-get install -y cloud-image-utils
fi

[[ -f "${SSH_PUBKEY_PATH}" ]] || {
  echo "SSH public key not found at ${SSH_PUBKEY_PATH}" >&2
  echo "Set SSH_PUBKEY_PATH=/path/to/key.pub and re-run." >&2
  exit 1
}
pubkey="$(cat "${SSH_PUBKEY_PATH}")"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

cat > "${workdir}/meta-data" <<EOF
instance-id: ${vm}
local-hostname: ${vm}
EOF

# 'runcmd' is left as a marker only - the actual NVIDIA driver install is a
# separate, deliberate step (06-guest-driver-install.sh) run once the guest
# is confirmed up, per the Stage 3 smoke-test gate.
cat > "${workdir}/user-data" <<EOF
#cloud-config
hostname: ${vm}
ssh_pwauth: false
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${pubkey}
package_update: true
runcmd:
  - [ "touch", "/var/lib/cloud/gb300-vm-ready" ]
EOF

out="${SEEDS_DIR}/${vm}-seed.iso"
cloud-localds "${out}" "${workdir}/user-data" "${workdir}/meta-data"
echo "wrote ${out}"
