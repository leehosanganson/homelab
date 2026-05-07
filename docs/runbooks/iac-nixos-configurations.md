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
│   ├── opencode-1/
│   ├── haproxy-{1,2,3}/
│   └── ...
├── keys/              # Pre-generated SSH host keys for sops-nix Day-0 bootstrap
│   └── <hostname>/etc/ssh/
├── modules/           # Reusable NixOS modules
│   ├── opencode.nix
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

---

## CPU Configuration

By default, VMs use `x86-64-v3` as the CPU type in Terraform to balance portability across Proxmox nodes with modern instruction support.

To expose host CPU instructions directly (useful for specific AI workloads), set `use_host_instruction = true` in `terraform/terraform.tfvars`. The default is `false`.
