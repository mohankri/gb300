#!/usr/bin/env bash
# Stage 2: render the libvirt domain XML for a VM from vars.sh's assignment
# table. adapted for this host's stock QEMU 8.2.2 / libvirt 10.0.0
# (plain smmuv3 iommu, no nested/iommufd - see the plan's grounding section).
# Usage: ./04-render-domain.sh <vm-name>
set -euo pipefail
source "$(dirname "$0")/vars.sh"

vm="${1:?usage: $0 <vm-name>}"
gpu="${VM_GPU[$vm]:?unknown vm: $vm}"
cpuset="${VM_CPUSET[$vm]}"
numa="${VM_NUMA[$vm]}"
mem_gib="${VM_MEMORY_GIB[$vm]}"

read -r gpu_domain gpu_bus gpu_slot gpu_func <<<"$(pci_addr_to_libvirt "${gpu}")"

IFS='-' read -r cpu_lo cpu_hi <<<"${cpuset}"
vcpu_count=$(( cpu_hi - cpu_lo + 1 ))

disk="${IMAGES_DIR}/${vm}.qcow2"
seed="${SEEDS_DIR}/${vm}-seed.iso"
vars_fd="${IMAGES_DIR}/${vm}-AAVMF_VARS.fd"
xml_out="${XML_DIR}/${vm}.xml"
uuid="$(uuidgen)"

[[ -f "${disk}" ]] || { echo "disk missing for ${vm}, run 03-make-disk.sh first" >&2; exit 1; }
[[ -f "${seed}" ]] || { echo "seed missing for ${vm}, run 02-make-seed.sh first" >&2; exit 1; }
[[ -f "${AAVMF_CODE}" ]] || { echo "AAVMF firmware not found at ${AAVMF_CODE}" >&2; exit 1; }

if [[ ! -f "${vars_fd}" ]]; then
  cp "${AAVMF_VARS_TEMPLATE}" "${vars_fd}"
  echo "created per-VM UEFI vars file: ${vars_fd}"
fi

vcpupin_xml=""
i=0
for pcpu in $(seq "${cpu_lo}" "${cpu_hi}"); do
  vcpupin_xml+="      <vcpupin vcpu='${i}' cpuset='${pcpu}'/>
"
  i=$((i+1))
done

mkdir -p "${XML_DIR}"

cat > "${xml_out}" <<XML
<domain type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0">
  <name>${vm}</name>
  <uuid>${uuid}</uuid>
  <memory unit="GiB">${mem_gib}</memory>
  <currentMemory unit="GiB">${mem_gib}</currentMemory>
  <memoryBacking>
    <hugepages>
      <page size="1" unit="G" nodeset="0"/>
    </hugepages>
    <allocation mode="immediate"/>
  </memoryBacking>
  <vcpu placement="static" cpuset="${cpuset}">${vcpu_count}</vcpu>
  <cputune>
${vcpupin_xml}  </cputune>
  <numatune>
    <memory mode="strict" nodeset="${numa}"/>
  </numatune>
  <os firmware="efi">
    <type arch="aarch64" machine="virt-8.2">hvm</type>
    <loader readonly="yes" type="pflash">${AAVMF_CODE}</loader>
    <nvram template="${AAVMF_VARS_TEMPLATE}">${vars_fd}</nvram>
    <boot dev="hd"/>
  </os>
  <cpu mode="host-passthrough" check="none"/>
  <features>
    <acpi/>
    <gic version="3"/>
  </features>
  <clock offset="utc"/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/bin/qemu-system-aarch64</emulator>
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2"/>
      <source file="${disk}"/>
      <target dev="vda" bus="virtio"/>
    </disk>
    <disk type="file" device="cdrom">
      <driver name="qemu" type="raw"/>
      <source file="${seed}"/>
      <target dev="sda" bus="sata"/>
      <readonly/>
    </disk>
    <interface type="network">
      <source network="default"/>
      <model type="virtio"/>
    </interface>
    <serial type="pty">
      <target type="system-serial" port="0">
        <model name="pl011"/>
      </target>
    </serial>
    <console type="pty">
      <target type="serial" port="0"/>
    </console>
    <hostdev mode="subsystem" type="pci" managed="yes">
      <source>
        <address domain="${gpu_domain}" bus="${gpu_bus}" slot="${gpu_slot}" function="${gpu_func}"/>
      </source>
    </hostdev>
    <iommu model="smmuv3"/>
    <rng model="virtio">
      <backend model="random">/dev/urandom</backend>
    </rng>
  </devices>
</domain>
XML

echo "wrote ${xml_out}"
if command -v virt-xml-validate >/dev/null 2>&1; then
  virt-xml-validate "${xml_out}" domain && echo "schema check: OK"
else
  echo "(virt-xml-validate not installed - skipping schema check)"
fi
