# Infrastructure as Code (IaC) — NixOS Configurations

This guide covers the full operational lifecycle for NixOS VMs in this homelab, from building the installer ISO through provisioning and day-to-day updates.

## Overview

The entire homelab is provisioned using a two-layer, fully declarative IaC approach:

- **Layer 1 — VM Lifecycle (OpenTofu):** OpenTofu manages the virtual hardware boundary of each NixOS VM on Proxmox — CPU, memory, disk, and network configuration. It leaves VMs powered off after creation; OS installation is handled by Layer 2. See [iac-terraform-opentofu-provisioning.md](./iac-terraform-opentofu-provisioning.md) for the full Terraform provisioning guide.
- **Layer 2 — OS & Configuration (NixOS):** Host configuration lives in [`nixos/`](../nixos/) as a Nix Flake. All provisioning uses `nixos-anywhere` + `disko`. Every change is declarative and reproducible.

## Directory Structure

```
nixos/
├── flake.nix          # Main flake entry point
├── flake.lock
├── hosts/             # Per-VM host configurations
│   ├── haproxy-{1,2,3}/
│   └── ...
├── keys/              # Pre-generated SSH host keys for sops-nix Day-0 bootstrap
│   └── <hostname>/etc/ssh/
├── modules/           # Reusable NixOS modules
│   ├── sops-bootstrap.nix
│   ├── haproxy.nix
│   └── ...
└── scripts/           # Provisioning and bootstrap scripts
    ├── provision.sh
    └── rebuild.sh
```

## Prerequisites

- **Nix with flakes enabled** — the `nix` CLI must have `experimental-features = nix-command flakes` set.
- **nixos-anywhere available** — either in your PATH or invoked via `nix run`.
- **SSH access to the Proxmox host** — required for uploading the installer ISO and for `nixos-anywhere` to reach the target VM.
- **sops age keys** — the age private key for decrypting secrets must be available locally; the corresponding public key must already be registered as a recipient in the GitHub Repository.

---

## Usage

### Look up declared IP addresses

From the repository root, run this read-only command with Python 3.9+ and Nix (`nix-instantiate`) on your `PATH`. No Python packages are needed.

```bash
python3 scripts/ip-inventory.py                # List covered addresses
python3 scripts/ip-inventory.py 192.168.1.151  # Look up one IPv4 or IPv6 address
```

Each IP appears once, with one entry per covered declaration. The source line, when
available, points to the host's `address` attribute or to the proxy module's config
option, not to an individual line in the rendered config. `vip` names identify
keepalived instances. `backend` entries show HAProxy backend/server names and ports,
not machine ownership. A lookup exits with status `1` if no covered declaration
matches, or `2` on invalid input or an evaluation error (including missing Nix).

The command uses restricted local Nix evaluation to read `networking.hostName` and
IPv4/IPv6 interface addresses from `nixos/hosts/*/default.nix`. It uses `haproxy-1`'s
networking to render `services.keepalived.extraConfig` and `services.haproxy.config`
from the shared `nixos/modules/haproxy.nix` once. It lists `virtual_ipaddress` entries
and named backend `server` endpoints with an IP and numeric port (brackets required
for IPv6). It does not merge NixOS module imports, evaluate the flake, build anything,
fetch inputs or secrets, resolve DNS, or check Terraform state, DHCP leases, or
running hosts. A miss does not mean the address is unused.

### 1. Provisioning

Provisioning is driven by the Terraform/OpenTofu module, which calls `nixos/scripts/provision.sh` to apply the flake onto each VM via `nixos-anywhere`.

Manual provisioning:

```bash
./nixos/scripts/provision.sh <hostname> <target-ip>
```

#### SSH Host Keys (Day-0 Bootstrap)

Before running `provision.sh`, pre-generate an SSH host key pair and place it under `nixos/keys/<hostname>/etc/ssh/`. `nixos-anywhere` will inject these into the installer VM so that:

1. The target VM has its host keys ready on first boot.
2. sops-nix can decrypt secrets immediately via the [`sops-bootstrap.nix`](../nixos/modules/sops-bootstrap.nix) module, which points `age.sshKeyPaths` at `/etc/ssh/bootstrap-vm` (injected by `provision.sh`).

### 2. Rebuilding

```bash
./nixos/scripts/rebuild.sh <hostname> <target-ip>
```

To pull the latest secrets revision before deploying, pass the optional flag:

```bash
./nixos/scripts/rebuild.sh --update-secrets <hostname> <target-ip>
```

---

## Secrets & SOPS

Each host imports [`sops-bootstrap.nix`](../nixos/modules/sops-bootstrap.nix) which configures sops-nix to use the bootstrap SSH key injected during provisioning. This eliminates per-host key management — all hosts share the same Day-0 decryption capability.

Encrypted secrets are stored in the external repository and referenced by each host's NixOS configuration via `defaultSopsFile`.

### Private flake input access

The NixOS flake includes the private `sops-secrets` Git repository as an input. Automatic upgrades use `/etc/ssh/bootstrap-vm` as the SSH identity for Git fetches by the `nixos-upgrade` service. This private key must be present and usable by root, and its associated GitHub account must have read access to the private `sops-secrets` repository. Provision and manage the private key outside this repository; do not store credentials here. Public read access to the `homelab` repository is also required.

The service accepts GitHub's ED25519 host key only. NixOS pins the key in `/etc/ssh/ssh_known_hosts` with fingerprint `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`; host-key checking is strict, and per-user known-host files are not used. If GitHub rotates this key, upgrades fail closed until the pin is updated after verifying the new key.

### Automatic upgrades

Each configured NixOS host uses the built-in `system.autoUpgrade` service to pull and switch to the `main` branch configuration for its own hostname from the `nixos/` flake directory in the public `homelab` repository. The service runs hourly, with a randomized delay of up to 15 minutes to spread builds across hosts. It uses the committed `flake.lock` and does not automatically reboot. A host switches to the new configuration only after its build succeeds.

---

## CPU Configuration

By default, VMs use `x86-64-v3` as the CPU type in Terraform to balance portability across Proxmox nodes with modern instruction support.

To expose host CPU instructions directly (useful for specific AI workloads), set `use_host_instruction = true` in `terraform/terraform.tfvars`. The default is `false`.
