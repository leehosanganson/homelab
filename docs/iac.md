# Infrastructure as Code (Iac)

## Terraform (OpenTofu) Provisioning

### Overview

This directory is **Layer 1** of a two-layer IaC stack. OpenTofu manages the virtual hardware boundary of each NixOS VM on Proxmox using the [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest) provider (`~> 0.104.0`).

**What it does:**

- Creates VMs with defined CPU, memory, disk, and network configuration
- Attaches a NixOS installer ISO on `ide2`
- Leaves VMs powered off (`started = false`) — OS installation is handled by Layer 2

**What it does not do:**

- Configure the OS (handled by `nixos-anywhere` + `disko` in `../nixos/`)
- Use Cloud-Init or any in-guest automation

---

### Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) installed
- Access to a Proxmox VE cluster
- A `terraform@pam` user with the `TerraformProv` role and an API token (see [Proxmox User Setup](#proxmox-user-setup))
- NixOS installer ISO uploaded to Proxmox storage (see [NixOS ISO](#nixos-iso))
- API token for `terraform@pam` stored in a local file (e.g. `~/.config/sops-nix/secrets/pve-terraform-api-token`)

---

### Proxmox User Setup

Create a least-privilege `terraform@pam` user with a custom `TerraformProv` role.

#### 1. Create the role with required privileges

Log into your Proxmox GUI.

Go to Datacenter > Permissions > Roles.

Click Create.

Name: TerraformProv

Privileges: Select the following (minimum requirements for most Terraform providers):

    VM/CT: VM.Allocate, VM.Config.CPU, VM.Config.Disk, VM.Config.HWType, VM.Config.Memory, VM.Config.Network, VM.Config.Options, VM.Audit, VM.PowerMgmt, VM.Console.

    Storage: Datastore.AllocateSpace, Datastore.Audit.

    System: Sys.Audit, Sys.Console.

    Pools: Pool.Allocate.

Click Create.

#### 2. Create the user

Navigate to Datacenter > Permissions > Users.

Click Add.

User name: terraform

Realm: Select pam (Linux PAM standard authentication).

Click Add.

#### 3. Create an API token

Run the following on the Proxmox host (or use the web UI under Datacenter > Permissions > API Tokens):

```bash
pveum user token add terraform@pam homelab --privsep=0
```

> **Important:** Copy the displayed secret immediately — it will never be shown again.

Save the token to a local file in the format `user@realm!tokenid=secret`:

```
terraform@pam!homelab=<uuid-secret>
```

For example:

```bash
echo "terraform@pam!homelab=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  > ~/.config/sops-nix/secrets/pve-terraform-api-token
chmod 600 ~/.config/sops-nix/secrets/pve-terraform-api-token
```

#### 4. Assign Permissions (ACLs)

> **Critical:** Both the **user** and the **token** must have their own ACL entries, even when `privsep=0`. With `privsep=0`, Proxmox still requires the user to have its own ACL — the token ACL alone is not sufficient.

```bash
# User ACL (required even with privsep=0)
pveum aclmod / --user terraform@pam --role TerraformProv

# Token ACL
pveum aclmod / --token terraform@pam!homelab --role TerraformProv
```

---

### ISO

The installer ISO is built from the NixOS flake in this repository.

#### Build the ISO

```bash
cd ../nixos
nix build .#packages.x86_64-linux.installer
# Output: result/iso/nixos-minimal-*.iso
```

#### Upload to Proxmox

Upload the ISO to a Proxmox storage (e.g. `local`) using `./nixos/scripts/sync-iso.sh`

```bash
cd ../nixos
./scripts/sync-iso.sh nixos/result/iso/nixos-*.iso pve01 pve02 pve03
```

#### Reference in tfvars

Set `nixos_iso` in `terraform.tfvars` to the Proxmox storage path:

```hcl
nixos_iso = "local:iso/nixos-minimal-26.05.20260302.cf59864-x86_64-linux.iso"
```

---

### Configuration

Copy or edit `terraform.tfvars` with values for your environment:

```hcl
proxmox_endpoint         = "https://pve01.home.lab:8006/"
proxmox_api_token_file   = "~/.config/sops-nix/secrets/pve-terraform-api-token"
proxmox_insecure         = true

pve_ssh_private_key_file = "~/.ssh/id_ed25519"

nixos_iso = "local:iso/nixos-minimal-*-linux.iso"

nodes = {
    // VM Configs here
    ...
}
```

Add additional entries to `nodes` for each VM to provision.

---

### Variables Reference

| Variable                   | Type          | Description                                                                    |
| -------------------------- | ------------- | ------------------------------------------------------------------------------ |
| `proxmox_endpoint`         | `string`      | HTTPS URL of the Proxmox API (e.g. `https://pve01.home.lab:8006/`)             |
| `proxmox_api_token_file`   | `string`      | Path to a local file containing the API token (`user@realm!tokenid=secret`)    |
| `proxmox_insecure`         | `bool`        | Skip TLS certificate verification (`true` for self-signed certs)               |
| `pve_ssh_private_key_file` | `string`      | SSH Key with permission ssh into the NixOS installer ISO                       |
| `nixos_iso`                | `string`      | Proxmox storage path to the NixOS installer ISO (e.g. `local:iso/nixos-*.iso`) |
| `nodes`                    | `map(object)` | Map of VM specs keyed by hostname — see below                                  |

| Attribute   | Type     | Description                                          |
| ----------- | -------- | ---------------------------------------------------- |
| `node`      | `string` | Proxmox node name to create the VM on (e.g. `pve01`) |
| `vm_id`     | `number` | Proxmox VM ID (must be unique cluster-wide)          |
| `cores`     | `number` | Number of vCPU cores                                 |
| `memory`    | `number` | RAM in MiB                                           |
| `disk_size` | `number` | Root disk size in GiB (provisioned on `scsi0`)       |
| `datastore` | `string` | Proxmox datastore for the disk (e.g. `local-lvm`)    |

---

### Usage

#### Initialise

```bash
tofu init
tofu plan
tofu apply
```

---

## NixOS Configurations

This guide covers the full operational lifecycle for NixOS VMs in this homelab, from building the installer ISO through provisioning and day-to-day updates.

### Prerequisites

- **Nix with flakes enabled** — the `nix` CLI must have `experimental-features = nix-command flakes` set.
- **nixos-anywhere available** — either in your PATH or invoked via `nix run`.
- **SSH access to the Proxmox host** — required for uploading the installer ISO and for `nixos-anywhere` to reach the target VM.
- **sops age keys** — the age private key for decrypting secrets must be available locally; the corresponding public key must already be registered as a recipient in the sops-secrets repository.

---

### Usage

#### 1. Provisioning as Terraform Module

Terraform module should execute the `./nixos/scripts/provision.sh` according to the spec and apply the flakes onto the VM.

Otherwise,

```bash
./nixos/scripts/provision.sh hostname 192.168.1.x
```

To inject pre-generated SSH host keys for sops-nix Day-0 secret decryption, place them under `nixos/scripts/keys/<hostname>/etc/ssh/` before running `provision.sh`.

#### 2. Rebuilding

```bash
./nixos/scripts/rebuild.sh hostname 192.168.1.x
```

To pull the latest secrets revision before deploying, pass the optional flag:

```bash
./nixos/scripts/rebuild.sh --update-secrets hostname 192.168.1.x
```

---

## Gotchas & Lessons Learned

### DHCP IP vs Static IP

After `tofu apply`, the VM is powered off. You must **start it manually** in Proxmox first. On first boot it gets a DHCP IP — find it from the Proxmox console (VM > Summary > IPs, or check your DHCP server). Use this DHCP IP for `provision.sh`. After provisioning, the flake configures a static IP — use **that static IP** for all subsequent `rebuild.sh` calls.

### Root SSH Access Required for rebuild.sh

`rebuild.sh` connects as `root`. The NixOS config must include your SSH public key in `users.users.root.openssh.authorizedKeys.keys`.

### Both User and Token Need ACLs (privsep=0 is not enough)

Even with `privsep=0`, Proxmox requires **both** the user (`terraform@pam`) and the token (`terraform@pam!homelab`) to have explicit ACL entries. The token ACL alone is not sufficient. Always run both:

```bash
pveum aclmod / --user terraform@pam --role TerraformProv
pveum aclmod / --token terraform@pam!homelab --role TerraformProv
```

### Use pam Realm, Not pve Realm

Create the Terraform user in the `pam` realm (`terraform@pam`), not `pve` (`terraform@pve`). In Proxmox 8.4, `pve` realm token ACLs are not evaluated correctly, causing persistent 403 errors even with correct ACL entries.

---
