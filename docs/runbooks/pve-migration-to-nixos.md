# PVE VM Migration — native Ubuntu VM → NixOS provisioning framework

Runbook for migrating a **manually-managed native Ubuntu VM** on Proxmox VE to
the homelab's two-layer **NixOS IaC** framework (OpenTofu for the VM lifecycle +
`nixos-anywhere`/`disko` for the OS).

Throughout, **Pi-hole is used as the worked example**: the two Pi-hole DNS
resolvers (VM 102/103) were the first services migrated with this flow. The same
steps apply to any other stateless-to-lightly-stateful VM; *k3s are handled by a
follow-up runbook* (their cluster state lives in etcd, which changes the
cutover, so they're deliberately out of scope here).

## Core principle: state is discardable, config is not

On a native Ubuntu VM, an app's config lives in hand-edited files on disk — that
state had to be backed up, migrated, and restored.

On NixOS the **entire desired state is declared in the flake**
(`nixos/modules/<app>.nix` + `nixos/hosts/<host>/default.nix`). The disk
contents are throwaway. For Pi-hole specifically:

| What used to be on-disk state | Now declared in the flake |
| ----------------------------- | ------------------------- |
| Adlists (`/etc/pihole/adlists.list`) | `homelab.pihole.blocklists` |
| Upstream DNS + local records | `settings.dns.*` in the module |
| OS / SSH / hardening           | shared `hardening.nix` module |
| Web admin password             | set once on first boot; intentionally not in git |

So there is **nothing to backup or transplant** from the old VM. You tear it
down and build the new one from the flake. This is what makes the migration safe
and fast.

## Migration targets (Pi-hole example)

| VM  | Host       | IP             | Role                      |
| --- | ---------- | -------------- | ------------------------- |
| 102 | `pihole-1` | `192.168.1.132`| Pi-hole DNS (primary)     |
| 103 | `pihole-2` | `192.168.1.133`| Pi-hole DNS (secondary)   |

**Constraint: keep the IPs (and VM IDs) the same** so downstream consumers
(nameserver entries, HAProxy backends `pihole_1/2`, Homepage widgets) never
change.

For a different service, replace the table with that service's VM IDs/IPs and
its module.

---

## 1) Uptime strategy — keep a peer/backup running

Do not accept downtime. Before touching the target, ensure a **backup of the
service is already serving**. For Pi-hole, redundancy is built in:

- **All machines/routers configure redundant nameservers** — they list **both**
  `192.168.1.132` and `192.168.1.133`, so DNS keeps resolving if either
  Pi-hole goes down.
- Migrate **one at a time**: while VM 102 is rebuilt, `.133` still serves.
  Order: **secondary first, then primary last** (`.132` is the more commonly
  configured resolver, so keep it up until the end).

For other services with only one instance, provision the NixOS replacement on a
spare node/IP first, validate, then cut over.

---

## 2) Cutover — tear down one VM, build it back from the flake

Per VM, on the management machine (flake checked out + Proxmox API token):

```bash
# 2.1 Import the existing VM so OpenTofu adopts (not duplicates) it by VM ID
cd terraform
tofu import 'proxmox_virtual_environment_vm.nixos["<host>"]' <vmid>

# 2.2 OpenTofu reconciles the VM + runs provision (nixos-anywhere) → wipes the
#     Ubuntu disk and installs NixOS from the flake
tofu plan
tofu apply -auto-approve
```

That's the whole cutover: **tear down, spin up from the flake.** No state to
carry over. If the new boot fails, nothing is lost — the old VM is gone but can
be recreated identically by re-running the same step (it's all in git), and the
peer/backup is still serving.

Repeat per VM (for Pi-hole: pihole-2 first, then pihole-1).

### Day-0 secrets

Runtime secrets are provided via **sops-nix** (encrypted in the external secrets
repo, decrypted at boot). For Pi-hole, the web/API admin password is injected
into the `pihole-ftl` service as the environment variable
`FTLCONF_webserver_api_pwhash` — so the generated `pihole.toml` stays read-only
(whether `readOnly` is on) and the password never lands in the repo.

**To add the Pi-hole password to sops:**

```bash
# 1. On any existing Pi-hole, generate the bcrypt hash of the password:
pihole setpassword        # or: pihole setpassword <secret>
# then read it back (it's stored under webserver.api.pwhash):
grep -E "pwhash" /etc/pihole/pihole.toml

# 2. Add a secret `pihole-web-pwhash` to the sops secrets repo containing the
#    env line that FTL expects:
#      FTLCONF_webserver_api_pwhash=<the-bcrypt-hash>
#    and push it (the `sops-secrets` flake input will pick it up on the next
#    `rebuild.sh --update-secrets`).
```

Then on the VM the `pihole-ftl` unit reads `/run/secrets/pihole-web-pwhash` via
`EnvironmentFile`, so no manual per-boot step is needed.

Also regenerate any downstream API keys (e.g. Homepage `HOMEPAGE_VAR_PIHOLE_*`)
to match the configured password.

---

## 3) Verify — service answers on the new resolver

```bash
# Service up on the static IP (e.g. DNS)
dig @<ip> google.com +short

# Blocking/dedup logic works (e.g. blocklist domain must NOT resolve)
dig @<ip> doubleclick.net +short

# Web UI up (direct + via proxy/TLS if applicable)
curl -fsS -o /dev/null -w "%{http_code}\n" http://<ip>/admin/

# Stateless = rebuild idempotency
cd nixos && ./scripts/rebuild.sh <host> <ip>
```

Confirm a downstream consumer that uses the *other* instance still worked while
this one was rebuilt (that's the uptime check), and that proxies/backends +
dashboards are green.

---

## 4) Gotchas

- **Nix flakes only see git-tracked files** — `git add` new `nixos/hosts/<name>`
  dirs before `nix build`/`eval`, or you hit *"Path ... is not tracked by Git"*.
- **`nodes` map must match reality** — `tofu import` by VM ID and confirm
  `node` with `qm config <id>`, or OpenTofu duplicates the VM.
- **App-specific conflicts** — e.g. `services.pihole-ftl` conflicts with
  `services.dnsmasq`; check the module's assertions before importing it.
- **Web UI changes don't persist** — NixOS modules often default to read-only
  config; change the flake and rebuild instead of click-saving in the GUI.
