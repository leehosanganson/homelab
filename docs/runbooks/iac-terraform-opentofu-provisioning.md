# Infrastructure as Code (IaC) — Terraform (OpenTofu) Provisioning

## Overview

This directory is **Layer 1** of a two-layer IaC stack. OpenTofu manages the virtual hardware boundary of each NixOS VM on Proxmox using the [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest) provider (`~> 0.104.0`).

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
- A `terraform@pam` user with the `TerraformProv` role and an API token (see [Proxmox User Setup](#proxmox-user-setup))
- NixOS installer ISO uploaded to Proxmox storage (see [NixOS ISO](#nixos-iso))
- API token for `terraform@pam` stored in a local file (e.g. `~/.config/sops-nix/secrets/pve-terraform-api-token`)

---

## Proxmox User Setup

Create a least-privilege `terraform@pam` user with a custom `TerraformProv` role.

### 1. Create the role with required privileges

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

### 2. Create the user

Navigate to Datacenter > Permissions > Users.

Click Add.

User name: terraform

Realm: Select pam (Linux PAM standard authentication).

Click Add.

### 3. Create an API token

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

### 4. Assign Permissions (ACLs)

> **Critical:** Both the **user** and the **token** must have their own ACL entries, even when `privsep=0`. With `privsep=0`, Proxmox still requires the user to have its own ACL — the token ACL alone is not sufficient.

```bash
# User ACL (required even with privsep=0)
pveum aclmod / --user terraform@pam --role TerraformProv

# Token ACL
pveum aclmod / --token terraform@pam!homelab --role TerraformProv
```

---

## ISO

The installer ISO is built from the NixOS flake in this repository.

### Build the ISO

```bash
cd ../nixos
nix build .#packages.x86_64-linux.installer
# Output: result/iso/nixos-minimal-*.iso
```

### Upload to Proxmox

Upload the ISO to a Proxmox storage (e.g. `local`) using `./nixos/scripts/sync-iso.sh`

```bash
cd ../nixos
./scripts/sync-iso.sh nixos/result/iso/nixos-*.iso pve01 pve02 pve03
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
proxmox_endpoint         = "https://pve01.home.lab:8006/"
proxmox_api_token_file   = "~/.config/sops-nix/secrets/pve-terraform-api-token"
proxmox_insecure         = true

pve_ssh_private_key_file = "~/.ssh/id_ed25519"

nixos_iso = "local:iso/nixos-minimal-*-linux.iso"
use_host_instruction = false

nodes = {
    // VM Configs here
    ...
}
```

Add additional entries to `nodes` for each VM to provision.

---

## Variables Reference

| Variable                   | Type          | Description                                                                    |
| -------------------------- | ------------- | ------------------------------------------------------------------------------ |
| `proxmox_endpoint`         | `string`      | HTTPS URL of the Proxmox API (e.g. `https://pve01.home.lab:8006/`)             |
| `proxmox_api_token_file`   | `string`      | Path to a local file containing the API token (`user@realm!tokenid=secret`)    |
| `proxmox_insecure`         | `bool`        | Skip TLS certificate verification (`true` for self-signed certs)               |
| `pve_ssh_private_key_file` | `string`      | SSH Key with permission ssh into the NixOS installer ISO                       |
| `nixos_iso`                | `string`      | Proxmox storage path to the NixOS installer ISO (e.g. `local:iso/nixos-*.iso`) |
| `use_host_instruction`     | `bool`        | Use `cpu.type = "host"` to expose host instructions; keep `false` for portable CPU type |
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

## Usage

### Initialise

```bash
tofu init
tofu plan
tofu apply
```

---

# Infrastructure as Code (IaC) — Gotchas & Lessons Learned

## DHCP IP vs Static IP

After `tofu apply`, the VM is powered off. You must **start it manually** in Proxmox first. On first boot it gets a DHCP IP — find it from the Proxmox console (VM > Summary > IPs, or check your DHCP server). Use this DHCP IP for `provision.sh`. After provisioning, the flake configures a static IP — use **that static IP** for all subsequent `rebuild.sh` calls.

## Root SSH Access Required for rebuild.sh

`rebuild.sh` connects as `root`. The NixOS config must include your SSH public key in `users.users.root.openssh.authorizedKeys.keys`.

## Both User and Token Need ACLs (privsep=0 is not enough)

Even with `privsep=0`, Proxmox requires **both** the user (`terraform@pam`) and the token (`terraform@pam!homelab`) to have explicit ACL entries. The token ACL alone is not sufficient. Always run both:

```bash
pveum aclmod / --user terraform@pam --role TerraformProv
pveum aclmod / --token terraform@pam!homelab --role TerraformProv
```

## Use pam Realm, Not pve Realm

Create the Terraform user in the `pam` realm (`terraform@pam`), not `pve` (`terraform@pve`). In Proxmox 8.4, `pve` realm token ACLs are not evaluated correctly, causing persistent 403 errors even with correct ACL entries.

## Troubleshooting

### `kexec_file_load failed: Operation not permitted` / `Kexec failed` from the local-exec provisioner

**Symptom:** `tofu apply` fails on `terraform_data.wait_for_guest_ssh["<host>"]`; the local-exec provisioner output shows nixos-anywhere failing with `kexec_file_load failed: Operation not permitted` or `Kexec failed`.

**Root cause:** The target host is **already installed and running NixOS**, not booted from the installer ISO (the VM uses disk-first `boot_order` and the ISO is detached after install). The installed system imports `nixos/modules/hardening.nix`, which sets `security.protectKernelImage = true` → `kernel.kexec_load_disabled=1`, so the kexec that nixos-anywhere needs is rejected by the kernel. The problem is amplified by a tainted `terraform_data.wait_for_guest_ssh` resource, which re-runs `nixos/scripts/provision.sh` (→ nixos-anywhere → kexec) on every apply.

**Recovery:**

1. Verify the host is actually installed and healthy:

   ```bash
   ssh root@<ip> 'nixos-rebuild list-generations'
   ```

2. With the guard in `provision.sh` (skips hosts whose `/` mounts a block device), just re-run `tofu apply` — provisioning is skipped and the tainted resource converges. Alternatively, clear the taint manually:

   ```bash
   tofu untaint 'terraform_data.wait_for_guest_ssh["<host>"]'
   ```

**Forced reinstall (destructive):** Boot the VM from the installer ISO, then:

```bash
tofu taint 'terraform_data.wait_for_guest_ssh["<host>"]' && tofu apply
```

> **WARNING:** nixos-anywhere wipes the disk via disko. Only do this when you genuinely intend to reinstall the host.

### `error: Path 'nixos/hosts/<name>' in the repository ... is not tracked by Git`

**Symptom:** The flake pre-build in `provision.sh` fails with `error: Path 'nixos/hosts/<name>' in the repository ... is not tracked by Git`.

**Fix:** `git add` the new host directory (e.g. `git add nixos/hosts/<name>`) and commit it. Nix flakes only see git-tracked files, so an untracked host directory is invisible to `nix build`. See also gotcha #1 in [pve-migration-to-nixos.md](pve-migration-to-nixos.md).

### Reinstalling a node that's already part of the k3s cluster → node won't rejoin

**Symptom:** After a NixOS k3s node is reinstalled via nixos-anywhere, it stays `NotReady,SchedulingDisabled` (or just `NotReady`) in `kubectl get nodes`. For a **control-plane/server** node the local `k3s.service` crash-loops (systemd `Result: protocol`) with:

```
etcd cluster join failed: duplicate node name found, please use a unique name for this node
```

For an **agent** node the `k3s.service` runs, but loops with:

```
Node password rejected, duplicate hostname or contents of '/etc/rancher/node/password' may not match server node-passwd entry
```

**Root cause:** nixos-anywhere wipes the disk, destroying the node's cluster identity, but the cluster still holds the stale pre-reinstall identity:

- **server node:** a stale **etcd member** entry named after the node still exists in the cluster, so the reinstalled server can't rejoin as a duplicate name;
- **agent node:** the cluster still has the old **node-password** hash for the node's name, so the reinstalled agent's new password is rejected.

**Prevention:** `nixos/scripts/provision.sh` now skips provisioning (and lets `tofu apply` converge) when the target already boots an installed system, so an accidental re-provision of a clustered node should not happen. If it still does, recover as below.

**Recovery — agent node (e.g. `work-01`):**

1. Remove the stale Node object so the agent can re-register with its new password:

   ```bash
   kubectl delete node <agent-name>
   ```

2. Restart the agent on the host to re-register promptly (it may also do so on its own):

   ```bash
   ssh root@<ip> 'systemctl restart k3s'
   ```

3. Confirm it rejoins as `Ready`; a freshly re-registered node is schedulable by default.

**Recovery — control-plane/server node (e.g. `ctrl-04`):**

1. On a **healthy** surviving server (e.g. `ctrl-01`), list the etcd members to find the stale `k3s-<name>-<id>` member for the reinstalled node:

   ```bash
   sudo ETCDCTL_API=3 \
     ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
     ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
     ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
     etcdctl --endpoints=https://127.0.0.1:2379 member list
   ```

2. Remove the stale member by ID. This is non-destructive to data and safe **as long as the remaining members still form a quorum** (e.g. at least 2 of a 3-member cluster are healthy — verify with `etcdctl endpoint health` afterwards):

   ```bash
   sudo ETCDCTL_API=3 \
     ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
     ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
     ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
     etcdctl --endpoints=https://127.0.0.1:2379 member remove <MEMBER_ID>
   ```

3. The reinstalled server re-joins on its next startup (restart if needed: `ssh root@<ip> 'systemctl restart k3s'`), is added as a new etcd member and promoted to a voting (non-learner) member automatically.

4. If it comes back `SchedulingDisabled` (previously cordoned), uncordon it:

   ```bash
   kubectl uncordon <server-name>
   ```

5. Verify: `kubectl get nodes` shows all nodes `Ready`, and `kubectl get node <server-name> -o jsonpath='{.spec.unschedulable}'` is empty, with `etcdctl member list` showing the node as a `started` member.
