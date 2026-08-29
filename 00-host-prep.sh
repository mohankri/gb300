#!/usr/bin/env bash
# Stage 0: one-time host prep for GB300 4-VM GPU passthrough.
# Modifies shared host state (libvirtd, kernel modules, hugepage reservations,
# a new libvirt storage pool). Review before running. Idempotent - safe to re-run.
set -euo pipefail
source "$(dirname "$0")/vars.sh"

echo "== enabling libvirtd =="
sudo systemctl enable --now libvirtd
systemctl is-active libvirtd

echo "== loading vfio-pci =="
sudo modprobe vfio-pci
echo vfio-pci | sudo tee /etc/modules-load.d/vfio-pci.conf >/dev/null
if [[ -d /sys/module/vfio_pci ]]; then
  echo "vfio-pci loaded"
else
  echo "vfio-pci failed to load" >&2
  exit 1
fi

echo "== reserving 1G hugepages (${HUGEPAGES_PER_NODE} per node) =="
for node in 0 1; do
  path="/sys/devices/system/node/node${node}/hugepages/hugepages-1048576kB/nr_hugepages"
  echo "${HUGEPAGES_PER_NODE}" | sudo tee "${path}" >/dev/null
  got="$(cat "${path}")"
  echo "node${node}: requested ${HUGEPAGES_PER_NODE}, got ${got}"
  if [[ "${got}" -lt "${HUGEPAGES_PER_NODE}" ]]; then
    echo "WARNING: node${node} only reserved ${got}/${HUGEPAGES_PER_NODE} 1G hugepages." >&2
    echo "This can happen due to memory fragmentation on a host that's been up a" >&2
    echo "while. A host reboot with 'hugepagesz=1G hugepages=<N>' on the kernel" >&2
    echo "cmdline may be required. STOP and confirm before rebooting this shared host." >&2
  fi
done

echo "== creating directories =="
mkdir -p "${XML_DIR}" "${SCRIPTS_DIR}" "${DOCS_DIR}"
sudo mkdir -p "${IMAGES_DIR}" "${SEEDS_DIR}"
sudo chown "$(id -u):$(id -g)" "${IMAGES_DIR}" "${SEEDS_DIR}"

echo "== defining libvirt storage pool '${STORAGE_POOL_NAME}' at ${IMAGES_DIR} =="
if ! virsh pool-info "${STORAGE_POOL_NAME}" >/dev/null 2>&1; then
  virsh pool-define-as "${STORAGE_POOL_NAME}" dir --target "${IMAGES_DIR}"
  virsh pool-build "${STORAGE_POOL_NAME}"
  virsh pool-start "${STORAGE_POOL_NAME}"
  virsh pool-autostart "${STORAGE_POOL_NAME}"
else
  echo "pool already defined"
fi
virsh pool-info "${STORAGE_POOL_NAME}"

echo "Stage 0 complete."
