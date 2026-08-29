# GB300 4-VM GPU-passthrough scripts

All scripts are idempotent and meant to be run **manually, one at a time**, so
you can inspect output/state between steps. None of them auto-chain. Full
design/rationale: see the plan and `~/vms/docs/gb300-vm-investigation.md`.

Run everything from `~/vms/scripts` on `lambda-gpu`.

## Order of operations

### Stage 0 - one-time host prep
```bash
./00-host-prep.sh
```
Enables `libvirtd`, loads/persists `vfio-pci`, reserves 1G hugepages on NUMA
nodes 0/1, creates `~/vms/{xml,scripts,docs}` and `/data/vms/{images,seeds}`,
and defines the `vms-data` libvirt storage pool at `/data/vms/images`.
**Watch for the hugepage warning** - if reservation doesn't fully stick, that's
a "stop and confirm before rebooting the host" situation, not something to push
through silently.

### Stage 1 - base image + per-VM disk/seed
```bash
./01-fetch-base-image.sh                 # once, shared by all VMs
for vm in vm-gpu0 vm-gpu1 vm-gpu2 vm-gpu3; do
  ./02-make-seed.sh "$vm"
  ./03-make-disk.sh "$vm"
done
```

### Stage 2 - render domain XML
```bash
for vm in vm-gpu0 vm-gpu1 vm-gpu2 vm-gpu3; do
  ./04-render-domain.sh "$vm"
done
```
Inspect `~/vms/xml/<vm>.xml` before proceeding - especially the `<hostdev>`
PCI address and `<cputune>` pinning for each VM against the table in
`vars.sh`.

### Stage 3 - single-GPU smoke test (hard gate, do not skip)
```bash
./05-vm-lifecycle.sh start vm-gpu0
```
Then, on the **host**:
```bash
nvidia-smi                      # 0008:06:00.0 should be gone
lspci -k -s 0008:06:00.0        # should show "Kernel driver in use: vfio-pci"
```
Console/SSH into the guest (`virsh console vm-gpu0`, or SSH once it has a DHCP
lease on `virbr0`), confirm `lspci` sees `10de:31c2`, then run
`06-guest-driver-install.sh` **inside the guest** and verify `nvidia-smi`
works there.

Roll back and confirm the automatic vfio-pci -> nvidia handoff:
```bash
./05-vm-lifecycle.sh stop vm-gpu0
nvidia-smi                      # 0008:06:00.0 should be back
```
If any of this doesn't behave as expected, stop here and reassess before
touching the other 3 GPUs - this is the real test of plain (non-nested)
SMMUv3 VFIO passthrough on this host's stock QEMU/libvirt build.

### Stage 4 - scale to all 4 VMs
```bash
for vm in vm-gpu1 vm-gpu2 vm-gpu3; do
  ./05-vm-lifecycle.sh start "$vm"
done
./05-vm-lifecycle.sh status vm-gpu0
./05-vm-lifecycle.sh status vm-gpu1
./05-vm-lifecycle.sh status vm-gpu2
./05-vm-lifecycle.sh status vm-gpu3
nvidia-smi   # should show zero GPUs on the host while all 4 VMs are running
```

### Teardown / revert
```bash
./05-vm-lifecycle.sh stop vm-gpu0        # (repeat per VM)
./05-vm-lifecycle.sh undefine vm-gpu0    # removes the domain definition + nvram
nvidia-smi                               # confirm all 4 GPUs are back on the host
```

## Notes
* `SSH_PUBKEY_PATH` defaults to `~/.ssh/id_ed25519.pub` on the host - override
  if you use a different key: `SSH_PUBKEY_PATH=~/.ssh/id_rsa.pub ./02-make-seed.sh vm-gpu0`.
* Networking is the default NAT `virbr0` network (no host bridge changes).
  Reach guests via `virsh console <vm>` or SSH once they have a DHCP lease.
* No cross-VM NVLink/NCCL P2P - each VM's GPU is isolated by design (the
  NVSwitch/C2C fabric bridges stay on the host).
