# NixOS Operations Guide

This guide covers the full operational lifecycle for NixOS VMs in this homelab, from building the installer ISO through provisioning and day-to-day updates.

## Prerequisites

- **Nix with flakes enabled** — the `nix` CLI must have `experimental-features = nix-command flakes` set.
- **nixos-anywhere available** — either in your PATH or invoked via `nix run`.
- **SSH access to the Proxmox host** — required for uploading the installer ISO and for `nixos-anywhere` to reach the target VM.
- **sops age keys** — the age private key for decrypting secrets must be available locally; the corresponding public key must already be registered as a recipient in the sops-secrets repository.

## Layer 1 — VM Lifecycle (OpenTofu)

OpenTofu (`terraform/`) manages the virtual hardware boundary of each VM on Proxmox using the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) provider. It defines CPU, memory, disk size, and network — but intentionally avoids Cloud-Init or any OS-level configuration.

```bash
cd terraform
tofu init
tofu apply
```

## Layer 2 — OS & Configuration (NixOS + nixos-anywhere + disko)

Once OpenTofu creates the blank VMs, `nixos-anywhere` + `disko` remotely partitions the disk and installs NixOS from the flake in one step.

### Build the Installer ISO (One-Time Setup)

Build a minimal NixOS installer ISO, upload it to Proxmox storage, and reference it in `terraform.tfvars` as `nixos_iso`. OpenTofu will attach the ISO to new VMs so they boot into the installer.

```bash
cd nixos
nix build .#packages.x86_64-linux.installer
# result/iso/nixos-*.iso  →  upload to Proxmox
```

#### Upload ISO to Proxmox

**Option A — Web UI**

1. Open `https://<proxmox-host>:8006` in your browser and log in.
2. Navigate to **Datacenter → local storage → ISO Images** in the left-hand tree.
3. Click **Upload**.
4. Select `nixos/result/iso/nixos-*.iso` from your local machine.
5. Note the resulting storage path (e.g. `local:iso/nixos-<version>.iso`) and set it as `nixos_iso` in `terraform/terraform.tfvars`.

**Option B — CLI**

1. Identify the built ISO:
   ```bash
   ls nixos/result/iso/nixos-*.iso
   ```
2. Copy it to the Proxmox host's ISO directory:
   ```bash
   scp nixos/result/iso/nixos-*.iso root@<proxmox-host>:/var/lib/vz/template/iso/
   ```
3. Verify the upload was registered:
   ```bash
   pvesm list local
   ```
4. Set the ISO path as `nixos_iso` in `terraform/terraform.tfvars`.

> **Note**: Replace `local` with your actual Proxmox storage pool name if it differs (e.g. `pve-storage`).

### Initial Provisioning

Boot the VM from the installer ISO (start it in Proxmox), then run:

```bash
./nixos/scripts/provision.sh haproxy-1 192.168.1.251
```

This calls `nix run .#nixos-anywhere -- --flake .#haproxy-1 root@192.168.1.251`, which uses disko to partition `/dev/sda` and installs the full NixOS configuration in one shot.

To inject pre-generated SSH host keys for sops-nix Day-0 secret decryption, place them under `nixos/scripts/keys/<hostname>/etc/ssh/` before running `provision.sh`.

### Updating an Existing Host

```bash
./nixos/scripts/rebuild.sh haproxy-1 192.168.1.251
```

This runs `nixos-rebuild switch --flake .#haproxy-1 --target-host root@192.168.1.251`, which builds the new closure locally (the default) and activates it on the remote host over SSH.

To also pull the latest secrets revision before deploying, pass the optional flag:

```bash
./nixos/scripts/rebuild.sh --update-secrets haproxy-1 192.168.1.251
```

## Secrets (sops-nix)

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix). Each host expects a pre-generated SSH host key whose **public** key is registered as an age recipient in the sops-secrets repository. The corresponding **private** key is injected onto the host at provisioning time via `nixos-anywhere --extra-files` (stored locally in `./nixos/scripts/keys/<hostname>/etc/ssh/`, which is gitignored). On first boot, sops-nix uses the SSH host key to derive the age private key for decrypting secrets.
