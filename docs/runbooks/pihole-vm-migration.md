# Pi-hole VM Migration — native Ubuntu VM → NixOS provisioning framework

Migrate the two Pi-hole DNS resolvers from **manually-managed Ubuntu VMs**
(native Proxmox VMs, hand-edited config) to the homelab's two-layer **NixOS
IaC** framework (OpenTofu for the VM lifecycle + `nixos-anywhere`/`disko` for
the OS).

The same pattern in this runbook is the template for the **next migration: the
k3s control-plane/worker servers** — and ultimately for moving any VM between
PVE nodes for rolling node maintenance.

## Core principle: state is discardable, config is not

On a native Ubuntu VM the Pi-hole config lives in hand-edited files on disk
(`/etc/pihole/*`, `setupVars.conf`) — that's state you had to care about.

On NixOS the **entire desired state is declared in the flake**
(`nixos/modules/pihole.nix` + `nixos/hosts/pihole-*/default.nix`). The disk
contents are throwaway:
- Adlists → declared as `homelab.pihole.blocklists`
- Upstream DNS + local records (`dns.hosts`) → declared in the module
- OS/SSH/hardening → declared in the modules
- Web admin password → set once on first boot (`pihole setpasswd`); it's the
  only runtime state, and it's intentionally not in git

So there is **nothing to back up or transplant on the Pi-hole VMs.** The old VM
is torn down and the new one is built from the flake. This is what makes the
migration (and later node moves) safe and fast.

## Migration targets

| VM  | Host      | IP             | Role                      |
| --- | --------- | -------------- | ------------------------- |
| 102 | `pihole-1`| `192.168.1.132`| Pi-hole DNS (primary)     |
| 103 | `pihole-2`| `192.168.1.133`| Pi-hole DNS (secondary)   |

**Constraint: keep the IPs (and VM IDs) the same** so downstream consumers
(nameserver entries, HAProxy `pihole_1/2` backends, Homepage widgets) never
change.

---

## 1) Uptime strategy — let the peer Pi-hole carry DNS

Do **not** accept a DNS outage. Redundancy is already in place:

- Both machines/routers already list **both** Pi-holes (or the second one) as
  resolvers, and each Pi-hole points at the **other** as its own resolver
  (`pihole-1` → `.133`, `pihole-2` → `.132`).
- Therefore we migrate **one Pi-hole at a time**: while VM 102 is being rebuilt,
  192.168.1.133 (pihole-2) keeps serving the network. Then swap.

**Order:** migrate `pihole-2` (secondary) **first**, then `pihole-1` last —
because `.132` is the more commonly configured resolver, keep it up until the
end.

---

## 2) Cutover — tear down one VM, build it back from the flake

Per VM, on the management machine (flake checked out + Proxmox API token):

```bash
# 2.1 Import the existing VM so OpenTofu adopts (not duplicates) it by VM ID
cd terraform
tofu import 'proxmox_virtual_environment_vm.nixos["pihole-2"]' 103

# 2.2 OpenTofu reconciles the VM + runs provision (nixos-anywhere) → wipes the
#     Ubuntu disk and installs NixOS from the flake
tofu plan
tofu apply -auto-approve
```

That's the whole cutover: **tear down, spin up from the flake.** No state to
carry over, no snapshot-to-migrate. If the new boot fails, nothing is lost —
the old VM is gone but can be recreated identically by re-running the same
tofu/provision step (it's all in git), and the peer Pi-hole is still serving.

After it verifies (§3), repeat for `pihole-1` (vm 102, `192.168.1.132`).

### Day-0 web password

On the freshly built VM once:

```bash
ssh root@192.168.1.133
pihole setpasswd
```

Then regenerate Homepage's `HOMEPAGE_VAR_PIHOLE_*_API_KEY` to match and push the
secrets. (sops-nix declarative password is a possible follow-up.)

---

## 3) Verify — DNS and blocking on the new resolver

```bash
# Resolver answers
dig @192.168.1.133 google.com +short

# Blocking active (blocklist domain must NOT return a real A record)
dig @192.168.1.133 doubleclick.net +short

# Web UI up (direct + via HAProxy/TLS)
curl -fsS -o /dev/null -w "%{http_code}\n" http://192.168.1.133/admin/
curl -fsS -o /dev/null -w "%{http_code}\n" https://pihole-2.infra.leehosanganson.dev/admin/

# Stateless = rebuild idempotency
cd nixos && ./scripts/rebuild.sh pihole-2 192.168.1.133
```

Confirm a host that uses `.132` still resolves while `.133` was being rebuilt
(that's the uptime check), and that HAProxy backends + Homepage are green.

---

## 4) Ledger — first migration, then scale the pattern

- **This PR:** the two Pi-hole VMs. Stateless → teardown/rebuild is trivial.
- **Next: k3s servers.** Same principle, with one caveat — k3s *nodes* carry
  cluster state (etcd for control-plane, static pods for work). For those, the
  "state is discardable" rule applies to the **node OS** only; the cluster state
  lives in etcd (a.k.a. the control-plane API), so you migrate one node at a
  time and let the cluster self-heal via the other members. The migrate-one-
  at-a-time + peer-redundancy pattern carries over directly.
- **Rolling node maintenance** (the long-term goal): because nodes are built
  entirely from the flake (+ otel/talos config), any VM can be re-provisioned
  identically (same IP) on another node — the same teardown/rebuild flow, with
  short-downtime windows acceptable.

---

## 5) Gotchas

- **Nix flakes only see git-tracked files** — `git add` new `nixos/hosts/<name>`
  dirs before `nix build`/`eval`, or you hit *"Path ... is not tracked by Git"*.
- **`nodes` map must match reality** — `tofu import` by VM ID and confirm
  `node` with `qm config <id>`, or tofu duplicates the VM.
- **`services.pihole-ftl` conflicts with `services.dnsmasq`** — don't enable both.
- **`lists` needs the webserver + `webserver.api.cli_pw = true`** (set in the
  module) or the build asserts.
- **Web UI changes don't persist** — the module defaults to read-only config;
  change the flake and rebuild, don't click-save in the GUI.
