# Terraform (OpenTofu) — Layer 1: VM Provisioning

## Overview

This directory is **Layer 1** of a two-layer IaC stack. OpenTofu manages the virtual hardware boundary of each NixOS VM on Proxmox using the [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest) provider (`~> 0.78`).

**What it does:**
- Creates VMs with defined CPU, memory, disk, and network configuration
- Attaches a NixOS installer ISO on `ide2`
- Leaves VMs powered off (`started = false`) — OS installation is handled by Layer 2

**What it does not do:**
- Configure the OS (handled by `nixos-anywhere` + `disko` in `../nixos/`)
- Use Cloud-Init or any in-guest automation

---

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) installed
- Access to a Proxmox VE cluster
- A `terraform@pve` user with the `Terraform` role (see [Proxmox User Setup](#proxmox-user-setup))
- NixOS installer ISO uploaded to Proxmox storage (see [NixOS ISO](#nixos-iso))
- Password for `terraform@pve` stored in a local file (e.g. `~/.config/sops-nix/secrets/pve-terraform-key`)

---

## Proxmox User Setup

Create a least-privilege `terraform@pve` user with a custom `Terraform` role. Run these commands on the Proxmox host (as root) or via `pvesh`.

### 1. Create the role with required privileges

```bash
pveum role add Terraform -privs \
  "VM.Allocate \
   VM.Config.CPU \
   VM.Config.Memory \
   VM.Config.Disk \
   VM.Config.CDROM \
   VM.Config.Network \
   VM.Config.Options \
   VM.Config.HWType \
   VM.GuestAgent.Unrestricted \
   VM.Audit \
   VM.PowerMgmt \
   Datastore.AllocateSpace \
   Datastore.Audit"
```

### 2. Create the user

```bash
pveum user add terraform@pve --comment "OpenTofu provisioning user"
pveum passwd terraform@pve
```

### 3. Assign the role at the root path (cluster-wide)

```bash
pveum aclmod / -user terraform@pve -role Terraform
```

### 4. Store the password in a local file

```bash
mkdir -p ~/.config/sops-nix/secrets
echo -n 'your-password-here' > ~/.config/sops-nix/secrets/pve-terraform-key
chmod 600 ~/.config/sops-nix/secrets/pve-terraform-key
```

---

## NixOS ISO

The installer ISO is built from the NixOS flake in this repository.

### Build the ISO

```bash
cd ../nixos
nix build .#packages.x86_64-linux.installer
# Output: result/iso/nixos-minimal-*.iso
```

### Upload to Proxmox

Upload the ISO to a Proxmox storage (e.g. `local`) via the web UI or:

```bash
scp result/iso/nixos-minimal-*.iso root@pve01:/var/lib/vz/template/iso/
```

### Reference in tfvars

Set `nixos_iso` in `terraform.tfvars` to the Proxmox storage path:

```hcl
nixos_iso = "local:iso/nixos-minimal-26.05.20260302.cf59864-x86_64-linux.iso"
```

---

## Configuration

Copy or edit `terraform.tfvars` with values for your environment:

```hcl
proxmox_endpoint      = "https://pve01.home.lab:8006/"
proxmox_username      = "terraform@pve"
proxmox_password_file = "~/.config/sops-nix/secrets/pve-terraform-key"
proxmox_insecure      = false

nixos_iso = "local:iso/nixos-minimal-26.05.20260302.cf59864-x86_64-linux.iso"

nodes = {
  "haproxy-2" = {
    node      = "pve01"
    vm_id     = 901
    cores     = 2
    memory    = 4096
    disk_size = 20
    datastore = "local-lvm"
  }
}
```

Add additional entries to `nodes` for each VM to provision.

---

## Usage

### Initialise

```bash
tofu init
```

### Plan

```bash
tofu plan
```

### Apply

```bash
tofu apply
```

VMs are created in a powered-off state. Proceed to [Full Workflow](#full-workflow) to install NixOS.

### Destroy

```bash
tofu destroy
```

> **Warning:** This permanently deletes all VMs managed by this configuration.

---

## Full Workflow

End-to-end steps from zero to a running NixOS VM.

### Step 1 — Build and upload the installer ISO

```bash
cd ../nixos
nix build .#packages.x86_64-linux.installer
scp result/iso/nixos-minimal-*.iso root@pve01:/var/lib/vz/template/iso/
```

Update `nixos_iso` in `terraform.tfvars` with the uploaded filename.

### Step 2 — Provision VM hardware

```bash
cd ../terraform
tofu init
tofu apply
```

VMs are created but not started.

### Step 3 — Boot from ISO

In the Proxmox web UI (or via CLI), start the VM. It will boot into the NixOS minimal installer from the attached ISO.

```bash
# Via CLI (replace 901 with the vm_id, pve01 with the node name)
ssh root@pve01 "qm start 901"
```

### Step 4 — Install NixOS (Layer 2)

Once the VM is booted into the installer and reachable over SSH, run `nixos-anywhere`:

```bash
../nixos/scripts/provision.sh haproxy-2 192.168.1.252
```

This partitions the disk with `disko` and installs the full NixOS configuration in one step. The VM will reboot into NixOS on completion.

> To inject pre-generated SSH host keys for `sops-nix` Day-0 secret decryption, place them under `../nixos/scripts/keys/<hostname>/etc/ssh/` before running `provision.sh`.

### Step 5 — Subsequent OS updates

```bash
../nixos/scripts/rebuild.sh haproxy-2 192.168.1.252

# To also pull the latest secrets revision before deploying:
../nixos/scripts/rebuild.sh --update-secrets haproxy-2 192.168.1.252
```

### Step 6 — Tear down

```bash
tofu destroy
```

---

## Variables Reference

| Variable | Type | Description |
|---|---|---|
| `proxmox_endpoint` | `string` | HTTPS URL of the Proxmox API (e.g. `https://pve01.home.lab:8006/`) |
| `proxmox_username` | `string` | Proxmox user in `user@realm` format (e.g. `terraform@pve`) |
| `proxmox_password_file` | `string` | Path to a local file containing the Proxmox user password |
| `proxmox_insecure` | `bool` | Skip TLS certificate verification (`true` for self-signed certs) |
| `nixos_iso` | `string` | Proxmox storage path to the NixOS installer ISO (e.g. `local:iso/nixos-*.iso`) |
| `nodes` | `map(object)` | Map of VM specs keyed by hostname — see below |

### `nodes` object attributes

| Attribute | Type | Description |
|---|---|---|
| `node` | `string` | Proxmox node name to create the VM on (e.g. `pve01`) |
| `vm_id` | `number` | Proxmox VM ID (must be unique cluster-wide) |
| `cores` | `number` | Number of vCPU cores |
| `memory` | `number` | RAM in MiB |
| `disk_size` | `number` | Root disk size in GiB (provisioned on `scsi0`) |
| `datastore` | `string` | Proxmox datastore for the disk (e.g. `local-lvm`) |

---

## Outputs

| Output | Description |
|---|---|
| `vm_ids` | Map of hostname → Proxmox VM ID for all provisioned VMs |

Retrieve after apply:

```bash
tofu output vm_ids
```
