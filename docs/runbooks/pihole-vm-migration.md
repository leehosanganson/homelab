# Pi-hole VM Migration — native Proxmox VM → NixOS provisioning framework

Runbook for migrating the two Pi-hole DNS resolvers from **native Proxmox VMs**
(manually created) to the homelab's two-layer **NixOS IaC** framework
(OpenTofu for the VM lifecycle + `nixos-anywhere`/`disko` for the OS).

The end goal of this work (and the reason the config is fully declarative) is
to be able to **move any VM to another Proxmox node** so we can do rolling node
maintenance without a long DNS outage. Because the entire OS is reproducible
from the flake, a Pi-hole can be re-provisioned identically on any node — the
same config, the same IP.

## Migration targets

| VM | Host  | IP           | Role                     |
| -- | ----- | ------------ | ------------------------ |
| 102 | `pihole-1` | `192.168.1.132` | Pi-hole DNS (primary)    |
| 103 | `pihole-2` | `192.168.1.133` | Pi-hole DNS (secondary)  |

**Constraint: keep the IPs (and ideally the VM IDs) the same.** Downstream
consumers that depend on these addresses must not break:
- `nixos/installer`, `nixos/hosts/*` nameserver entries (`192.168.1.132`)
- HAProxy backends `pihole_1` / `pihole_2` (`192.168.1.132:80`, `192.168.1.133:80`)
- Homepage widgets / API keys for `pihole-1/2.infra.leehosanganson.dev`

---

## 1) Preflight — inspect the current VMs (do this BEFORE any change)

Collect a full picture of the running Pi-hole before touching anything.

### 1.1 Inventory the VM on Proxmox

These run against the **Proxmox host** (the node the VM lives on):

```bash
# Which node hosts each VM, current config, and status
qm config 102
qm config 103
qm status 102
qm status 103

# Confirm which node the VM actually runs on
qm list | grep -E "102|103"
```

Look for: `cores`, `memory`, `scsi0`/`virtio0` disk size + `storage`, the
`vmbr0`/VLAN, and the MAC. The OpenTofu `nodes` map in
`terraform/terraform.tfvars` must match the *existing* node and we re-use the
same `vm_id` (102/103), so `tofu apply` adopts rather than duplicates.

### 1.2 Inspect the running Pi-hole OS

SSH into each VM:

```bash
ssh root@192.168.1.132
ssh root@192.168.1.133

# What OS / how Pi-hole was installed
cat /etc/os-release
pihole version
systemctl status pihole-FTL --no-pager | head -20
```

### 1.3 Export Pi-hole configuration & data

The point of going declarative is that these become code — so capture what
exists today and translate it into `nixos/modules/pihole.nix` and secrets.

```bash
# 1. Full configuration summary (settings, DNS, DHCP)
pihole -a -c        # current config/settings
pihole -a -H        # DHCP settings (if DHCP is enabled on the VM)

# 2. Adlists — these go into the module's `lists = [...]`
pihole -g -l        # adlists, shows enabled + status
sqlite3 /etc/pihole/gravity.db "SELECT address, enabled FROM adlist;"

# 3. Custom allow/deny lists (whitelist/blacklist / regex)
sqlite3 /etc/pihole/gravity.db \
  "SELECT type, domain, enabled FROM domainlist;"

# 4. Local DNS records (custom CNAME/A records)
cat /etc/pihole/custom.list 2>/dev/null

# 5. Upstream DNS servers currently in use
grep -E "upstreams|dns" /etc/pihole/pihole.toml 2>/dev/null \
  || grep -E "server=" /etc/pihole/setupVars.conf 2>/dev/null

# 6. Web/API app password — the APP password used by Homepage
#    (stored as a hash in pihole.toml; see "Secrets" below)
grep -A2 "webserver.api.password" /etc/pihole/pihole.toml 2>/dev/null
```

### 1.4 Capture the query log/DB (optional, for continuity)

Pi-hole keeps stats in `pihole-FTL.db`. If you want query history continuity,
copy it over during cutover:

```bash
scp root@192.168.1.132:/etc/pihole/gravity.db ./gravity-102.db
```

On a fresh NixOS provision the module's `pihole-ftl-setup` unit already
downloads the `lists` and runs `gravity` on first boot, so adlists don't need
manual DB transplanting — only the allow/deny and local DNS records above.

---

## 2) What this migration PR adds

The code is the deliverable of this PR:

| Path | Purpose |
| ---- | ------- |
| `nixos/modules/pihole.nix` | **Shared** Pi-hole config used by both VMs (service, upstream DNS, blocklists, firewall). |
| `nixos/hosts/pihole-1/default.nix` | pihole-1 host: imports module, sets **192.168.1.132**. |
| `nixos/hosts/pihole-2/default.nix` | pihole-2 host: imports module, sets **192.168.1.133**. |
| `nixos/flake.nix` | Registers `nixosConfigurations.pihole-1` and `pihole-2`. |
| `terraform/terraform.tfvars` | Adds `pihole-1` (vm 102) and `pihole-2` (vm 103) to the `nodes` map. |
| `docs/runbooks/pihole-vm-migration.md` | This runbook. |

Both hosts share `pihole.nix`; the only per-host difference is hostname + IP.
That is what makes the two resolvers interchangeable and node-portable.

### Secrets (web admin + API password)

The web UI password is **not** committed. Two supported options:

1. **Day-0 via `pihole setpasswd` (simplest):** after first boot, on the VM run
   `pihole setpasswd`. The hash is written by FTL into `/etc/pihole/pihole.toml`
   at runtime. Note the module writes this file with `mode 400` from the store,
   so the runtime hash lives alongside; treat the VM state as holding it.
2. **Declarative via sops-nix (recommended long-term):** add a `pihole-web-password`
   secret and render it into the config. Extend `nixos/modules/pihole.nix`
   (sops block) following the existing `opencode-1` / `haproxy-1` patterns.

Homepage's `HOMEPAGE_VAR_PIHOLE_1/2_API_KEY` secret should be regenerated to
match whatever password you set, updated in the sops `secrets.yaml`, and pushed
to the external secrets repo before cutover.

---

## 3) Pre-provisioning checklist

Before touching the cluster, on the **management machine** (where you have the
flake checked out and a Proxmox API token):

```bash
# 3.1 Build + sync the NixOS installer ISO to all PVE nodes
cd nixos
nix build .#packages.x86_64-linux.installer
./scripts/sync-iso.sh \
  "$(echo result/iso/nixos-minimal-*.iso)" pve01 pve02 pve03

# 3.2 Generate SSH host keys for Day-0 sops bootstrap (gitignored)
#     for each host, matching the layout provision.sh expects:
#     nixos/scripts/keys/<hostname>/etc/ssh/ssh_host_ed25519_key(.pub)
ssh-keygen -t ed25519 -f nixos/scripts/keys/pihole-1/etc/ssh/ssh_host_ed25519_key -N "" -C pihole-1
ssh-keygen -t ed25519 -f nixos/scripts/keys/pihole-2/etc/ssh/ssh_host_ed25519_key -N "" -C pihole-2
```

---

## 4) Cutover — migrate the VMs

There are two viable cutover strategies. **Pick one** and record it.

### Strategy A — Re-provision in place (re-use VM 102/103 directly)

Suitable when the existing VM can be torn down (no separate shared-storage
backup needed) and you accept one short DNS outage per VM.

```bash
# 1. Optional: snapshot/duplicate the old disk for rollback
#    (on the PVE host)
qm snapshot 102 pre-migration

# 2. From terraform/
cd ../terraform
# Import the EXISTING VM so tofu adopts it instead of trying to create a new one.
tofu import 'proxmox_virtual_environment_vm.nixos["pihole-1"]' 102
tofu import 'proxmox_virtual_environment_vm.nixos["pihole-2"]' 103

# 3. Power off, attach the installer ISO, boot to it (the module's lifecycle
#    already manages CDROM/boot_order through tofu apply)
tofu plan
tofu apply -auto-approve

# 4. tofu apply runs ../nixos/scripts/provision.sh <host> <ip> via
#    nixos-anywhere + disko, which wipes the disk and installs NixOS.
```

Then verify (section 5) and repeat for VM 103.

### Strategy B — Maintain a spare resolver through cutover (reduced risk)

For near-zero DNS downtime, stand up the NixOS pihole on a **new** VM / spare
node *first* using a temporary IP, validate, then move it onto the target IP
by powering off the old VM and letting DHCP/ARP settle:

```bash
# In tfvars, point pihole-2 at a spare node/IP temporarily, provision+validate,
# then flip it back to 192.168.1.133 and tofu apply again once the old VM is off.
```

> Because pihole-1 at .132 is the configured nameserver basically everywhere,
> do pihole-1 LAST and keep the outage to seconds. Or better: migrate pihole-2
> first, then pihole-1.

---

## 5) Post-provisioning verification

After each host is up on NixOS:

```bash
# 5.1 It's listening on the static IP
ping -c2 192.168.1.132
ssh root@192.168.1.132

# 5.2 DNS resolves through the new resolver (adjust IP per VM)
dig @192.168.1.132 google.com +short
dig @192.168.1.132 example.com A

# 5.3 Blocking works (confirm a blocklist domain is NXDOMAIN/0.0.0.0)
dig @192.168.1.132 doubleclick.net +short
#   -> should NOT return a real A record

# 5.4 FTL + web are healthy
systemctl status pihole-ftl --no-pager | head
curl -fsS -o /dev/null -w "%{http_code}\n" http://192.168.1.132/admin/

# 5.5 The web UI is reachable via HAProxy + TLS
curl -fsS -o /dev/null -w "%{http_code}\n" \
  https://pihole-1.infra.leehosanganson.dev/admin/

# 5.6 Confirmed the pihole-ftl-setup unit loaded the blocklists
journalctl -u pihole-ftl-setup --no-pager | tail -20

# 5.7 Rebuild idempotency check (config is fully declarative)
cd nixos && ./scripts/rebuild.sh pihole-1 192.168.1.132
```

### Cross-check consumers didn't break

- `ssh` from a NixOS host that defines `nameservers = [ "192.168.1.132" ]`
  (e.g. `hermes-agent`) still resolves.
- Homepage shows live Pi-hole stats (API key valid).
- HAProxy backends green: `https://pihole-1.infra...` and `pihole-2.infra...`.

---

## 6) Rollback

- If you snapshotted in Strategy A: on the PVE host
  `qm rollback 102 pre-migration`, then `qm start 102`.
- Without a snapshot, the old VM root disk (`local-lvm`) is wiped by disko —
  restore from your Pi-hole backup (gravity DB + adlists captured in §1).
- If DNS breaks and old VMs are gone, temporarily point the HAProxy/consumer
  config at the *other* still-running resolver while you recover.

---

## 7) The end goal — VM mobility for rolling node maintenance

The reason everything above is declarative is so a VM is just "config + data,"
with no node affinity baked in. To move a Pi-hole (or any NixOS VM) between
Proxmox nodes:

1. **Pick the target node** and update its `node` in `terraform.tfvars`.
2. **Storage matters.** `local-lvm` is node-local — a live migration needs
   shared storage (e.g. a Ceph/RBD or NFS-backed datastore) for zero-downtime
   `qm migrate`. Without it, do an offline migration:
   ```bash
   # on PVE source node
   qm migrate <vmid> <target-node> --online 0
   ```
   or, because the OS is reproducible, simply `tofu apply` with a changed
   `node`+`datastore` — tofu rebuilds the VM on the target and
   `nixos-anywhere` re-provisions it from the flake (keeps the same IP).
3. **Keep IP stable.** The flake pins the static IP, so after moving the VM the
   IP is unchanged — no downstream DNS/ARP churn. For truly zero-downtime
   migration you'd want a floating/live-migrated NIC; for rolling maintenance
   with short windows, rebuild-on-target is sufficient.
4. **Sequence for node maintenance:** (a) `nixos-rebuild`/tofu the VM onto a
   spare node, (b) validate §5, (c) then reboot/drain the original node.

### What this repo needs for full VM mobility

- A shared datastore across nodes (replace `local-lvm`) to enable online `qm
  migrate`. Tracked separately; the Pi-hole migration itself only needs the
  offline/rebuild path.
- (Optional) Move Pi-hole to a floating VIP if you ever need sub-second failover.

---

## 8) Useful gotchas & lessons learned

- **Nix flakes only see git-tracked files.** Before `nix build`/`eval`, `git add`
  the new `nixos/hosts/<name>` directory or you'll hit *"Path ... is not
  tracked by Git"*.
- **The `nodes` map must match reality or tofu duplicates VMs.** Always
  `tofu import` existing VMs by their VM ID, and confirm `node` with
  `qm config <id>`.
- **`services.pihole-ftl` conflicts with `services.dnsmasq`.** Don't enable
  both on the same host.
- **`lists` requires the webserver enabled + `webserver.api.cli_pw = true`**
  (set in the shared module) — otherwise the module asserts on build.
- **Declarative `readOnly = true` is the module default.** Config changes via
  the web UI/API won't persist across rebuilds — that's intentional here;
  change `nixos/modules/pihole.nix` and rebuild instead.
- **Firewall:** the module opens 53/tcp, 53/udp (+ 80 for the web UI, 22 for
  ssh). Confirm `networking.firewall.allowedTCPPorts = [22 53 80]` if you add
  anything else.
