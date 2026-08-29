# GB300

## Step 3 — Host topology and virtualization stack on `mohan-gpu`

### Command
```bash
ssh mohan-gpu bash -s <<'EOF'
lscpu
numactl -H
virsh --version
qemu-system-aarch64 --version
dpkg -l | grep -i libvirt | awk '{print $1,$2,$3}'
systemctl is-active libvirtd
lspci -D -nn | grep -i nvidia
for full in $(lspci -D | grep -i nvidia | awk '{print $1}'); do
  g=$(basename "$(readlink -f /sys/bus/pci/devices/$full/iommu_group)")
  echo "$full -> iommu_group $g"
done
ls -d /sys/kernel/iommu_groups/*/ | wc -l
sudo dmesg | grep -iE "iommu|smmu" | head -30
EOF
```

### Captured output — CPU
```
Architecture:                            aarch64
CPU(s):                                  144
Vendor ID:                               ARM
Model name:                              Neoverse-V2
Core(s) per socket:                      72
Socket(s):                               2
Thread(s) per core:                      1
```
2 sockets x 72 cores, no hyperthreading, 144 logical CPUs total.

### Captured output — NUMA (`numactl -H`)
```
available: 34 nodes (0-33)
node 0 cpus: 0-71
node 0 size: 483137 MB
node 1 cpus: 72-143
node 1 size: 481768 MB
node 2  size: 283136 MB   (no cpus)
node 3..9   size: 0 MB    (no cpus)
node 10     size: 283136 MB   (no cpus)
node 11..17 size: 0 MB    (no cpus)
node 18     size: 283136 MB   (no cpus)
node 19..25 size: 0 MB    (no cpus)
node 26     size: 283136 MB   (no cpus)
node 27..33 size: 0 MB    (no cpus)

node distances (abridged): nodes {2..9} are mutually close (11) and far (40) from
{10..17}/{18..25}/{26..33}; same pattern repeats for each group of 8.
```

**Finding:** nodes 0/1 are the two Grace CPU (LPDDR) sockets — matches 144 CPUs /
2 sockets. Nodes {2,10,18,26} are the 4 GPUs' HBM pools (283136 MB ≈ 276.5 GiB each,
consistent with the 284208 MiB/GPU noted during shard-lab). Each GPU's HBM node is
accompanied by 7 more zero-sized proximity-domain nodes (e.g. GPU 0 → nodes 2-9),
mirroring exactly the 8-`nodeid` / `acpi-generic-initiator` pattern hardcoded in
`gh200.1.j2` — except here it is *real* firmware-provided ACPI IORT/SRAT topology on
bare metal, not something QEMU has to synthesize for a guest. This confirms the
GB300 tray is architecturally GH200-like (Grace CPU + coherently-attached GPU per
NUMA domain), just scaled to 4 GPUs/2 CPU sockets instead of 1:1.

### Captured output — virtualization stack
```
virsh:    10.0.0
qemu-system-aarch64: QEMU emulator version 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.18)
libvirt-daemon, libvirt-daemon-driver-qemu, libvirt-daemon-system: 10.0.0-2ubuntu8.16 (stock Ubuntu 24.04 packages)
systemctl is-active libvirtd: inactive
```

**Finding:** `mohan-gpu` runs **stock Ubuntu-packaged QEMU 8.2.2 / libvirt 10.0.0**,
not mohan's downstream-patched hypervisor build referenced in `gh200.1.j2`'s
comments. `libvirtd` is installed but not currently running. Whether stock QEMU 8.2.2
supports the same `iommufd nested="on"` SMMUv3 passthrough path is an open risk to
validate directly (upstream nested-SMMU/iommufd guest support landed in stages across
QEMU 8.2–9.x; needs an empirical test on this exact build, not an assumption).

### Captured output — GPU PCI topology
```
0008:06:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:31c2] (rev a1)
0009:06:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:31c2] (rev a1)
0018:06:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:31c2] (rev a1)
0019:06:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:31c2] (rev a1)
```
(Each sits behind its own PCI-bridge function — `0008:00:00.0`, `0009:00:00.0`,
`0018:00:00.0`, `0019:00:00.0`, device id `10de:22b1` — in its own PCI domain/segment.
The remaining bridges seen at `0000/0002/0005/0006/0010/0012/0015/0016` (device ids
`10de:22b2`/`22b8`) are NVLink/C2C fabric bridges, not additional GPUs.)

### Captured output — IOMMU groups
```
0008:06:00.0 -> iommu_group 79
0009:06:00.0 -> iommu_group 80
0018:06:00.0 -> iommu_group 81
0019:06:00.0 -> iommu_group 82
Total iommu groups on host: 83
Devices sharing group 1 (bridge 0000:00:00.0): only itself
```

**Finding:** each of the 4 GPUs is alone in its own IOMMU group (79/80/81/82), and a
spot-check of a bridge's group shows no unwanted co-membership either. This is the
best-case scenario for VFIO passthrough — each GPU can be assigned to a separate VM
with no risk of also exposing an unrelated device on the same IOMMU group.

### Captured output — SMMU/IOMMU kernel status
```
[0.998227] ACPI: IORT: SMMU-v3[11000000] Mapped to Proximity domain 0
[0.998352] ACPI: IORT: SMMU-v3[100011000000] Mapped to Proximity domain 1
[42.324961] iommu: Default domain type: Translated
[42.333041] iommu: DMA domain TLB invalidation policy: strict mode
[47.447979] arm-smmu-v3 arm-smmu-v3.10.auto: ias 48-bit, oas 48-bit (features 0x000e1fbf)
... (one arm-smmu-v3.N.auto instance per SMMU, several found)
```

**Finding:** ARM SMMUv3 is enabled and active with a `Translated` default domain —
the host is already IOMMU/SMMU-capable at the kernel level, which is the prerequisite
for `vfio-pci` device isolation. `vfio-pci.ko` is present in the running kernel's
module tree (`/lib/modules/6.8.0-138-generic/kernel/drivers/vfio/pci/vfio-pci.ko.zst`)
but not currently loaded/bound to any device.

## Findings summary
| Question | Answer |
|---|---|
| GPUs on host | 4x GB300 (`10de:31c2`), each its own PCI domain, each alone in its own IOMMU group |
| CPU/NUMA layout | 2 sockets x 72 cores (144 total); nodes 0/1 = CPU memory; nodes 2/10/18/26 = one GPU's HBM each, each with 7 companion proximity-domain nodes |
| SMMU/IOMMU | ARM SMMUv3 active, `Translated` default domain — passthrough-capable |
| libvirt/QEMU | Stock Ubuntu 10.0.0 / 8.2.2 — **not** mohan's patched GH200/GB300 hypervisor fork |
| libvirtd | Installed, currently inactive |
| Closest mohan-dev template | `gh200.1.j2` (structurally analogous Grace+GPU coherent design) — reference only, assumes patches not present here |
| Existing GB300 vmslot in mohan-dev | `gb300.metal-4.sku23.yaml`, bare-metal stub only, no per-GPU slot carve-up |

## Open questions / risks carried into the plan
1. Whether stock QEMU 8.2.2 + libvirt 10.0.0 support nested SMMUv3 (`iommufd
   nested="on"`) VFIO passthrough on this Grace platform, or whether the coherent
   NVLink-C2C GPU attachment requires the patched fork `gh200.1.j2` warns about —
   needs an empirical single-GPU passthrough test before committing to 4 VMs.
2. Whether the 4 companion "proximity domain" NUMA nodes per GPU need to be
   reproduced inside each guest (as `gh200.1.j2` does via `acpi-generic-initiator`
   qemu args) for correct guest-side memory locality, or whether they're irrelevant
   without the coherent C2C link being passed through as well.
3. `libvirtd` needs to be started (and enabled) before any `virsh define` calls.
4. No production SKU/vmslot changes are in scope — this is a standalone, host-local
   libvirt setup under `~/vms`.
