# Infrastructure as Code (IaC) — NixOS Configurations

This guide covers the full operational lifecycle for NixOS VMs in this homelab, from building the installer ISO through provisioning and day-to-day updates.

## Prerequisites

- **Nix with flakes enabled** — the `nix` CLI must have `experimental-features = nix-command flakes` set.
- **nixos-anywhere available** — either in your PATH or invoked via `nix run`.
- **SSH access to the Proxmox host** — required for uploading the installer ISO and for `nixos-anywhere` to reach the target VM.
- **sops age keys** — the age private key for decrypting secrets must be available locally; the corresponding public key must already be registered as a recipient in the sops-secrets repository.

---

## Usage

### 1. Provisioning as Terraform Module

Terraform module should execute the `./nixos/scripts/provision.sh` according to the spec and apply the flakes onto the VM.

Otherwise,

```bash
./nixos/scripts/provision.sh hostname 192.168.1.x
```

To inject pre-generated SSH host keys for sops-nix Day-0 secret decryption, place them under `nixos/scripts/keys/<hostname>/etc/ssh/` before running `provision.sh`.

### 2. Rebuilding

```bash
./nixos/scripts/rebuild.sh hostname 192.168.1.x
```

To pull the latest secrets revision before deploying, pass the optional flag:

```bash
./nixos/scripts/rebuild.sh --update-secrets hostname 192.168.1.x
```

---
