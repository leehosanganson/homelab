# Technitium DNS cluster

This runbook covers the two NixOS Technitium DNS servers described in the
flake. It documents a manually initialized cluster and the declarative DNS
state that the NixOS hosts reconcile when they are running as its primary.

| Host | VM ID | Proxmox node | Static IPv4 | vCPU / memory / disk |
| --- | ---: | --- | --- | --- |
| `technitium-1` | 211 | `pve01` | `192.168.1.211` | 2 / 2048 MiB / 20 GiB |
| `technitium-2` | 212 | `pve04` | `192.168.1.212` | 2 / 2048 MiB / 20 GiB |

The VMs use the `local-lvm` datastore. Their NixOS configuration is in
`nixos/hosts/technitium-{1,2}`, the shared service/firewall and reconciliation
policy is in `nixos/modules/technitium.nix`, and the reconciliation program and
mocked API tests are in `nixos/scripts/`.

## Network and management access

Technitium DNS clustering synchronizes configuration between nodes; each node
still answers DNS independently. The upstream clustering design uses encrypted
node-to-node TLS (DANE-EE) on the Technitium web-service port. The NixOS module
opens DNS TCP/UDP port 53 to routed clients, without a source-subnet restriction,
and permits HTTPS TCP port 53443 only from the other configured Technitium
node. Admin HTTP TCP port 5380 is permitted only on `eth0` from the HAProxy
hosts (`192.168.1.251`, `.252`, and `.253`); it is not open to general clients.
The HAProxy HTTPS routes use the wildcard certificate and forward HTTP to each
node's port 5380:

- `https://technitium-1.infra.leehosanganson.dev` → `192.168.1.211:5380`
- `https://technitium-2.infra.leehosanganson.dev` → `192.168.1.212:5380`

These browser routes are available after the HAProxy and Technitium NixOS
configurations have been activated. TLS terminates at HAProxy; its backend
connection to Technitium uses HTTP on the private network. HTTPS port 53443
remains peer-only and is not the browser backend. Because these resolvers use
private IP addresses, perimeter routing and firewalls must prevent DNS, admin,
and peer traffic from being exposed to the public internet/WAN; do not add
public port forwarding. SSH remains key-only under the shared NixOS hardening
policy.

Before the proxy route is available, or when direct local access is needed, use
an SSH local port forward to loopback, for example:

```sh
ssh -L 5380:127.0.0.1:5380 ansonlee@192.168.1.211
```

Then open `http://127.0.0.1:5380` locally. Use the corresponding IP for the
second server. A local forward to `127.0.0.1:53443` can be used for HTTPS after
Technitium enables it. Protect the initial administrator account and use
Technitium's HTTPS/DANE-protected cluster connection for node-to-node traffic.
Do not add broad firewall access for the admin web service.

## Manual cluster initialization and join

Both hosts use the approved, fixed cluster identifier
`technitium-cluster.infra.leehosanganson.dev`. Technitium does not let this
identity change after initialization. Do not use another identifier.

Cluster creation and joining remain manual. Do not automate either action.
After both nodes are installed and reachable on their static IPs:

1. Configure administrator access and the HTTPS service in Technitium's web
   console. Upstream recommends a valid certificate before cluster
   initialization where available. If it is unavailable, review Technitium's
   certificate-validation options and risks before proceeding; the cluster
   uses DANE-EE for node-to-node authentication after joining.
2. Log in to `technitium-1`, then use **Administration > Cluster > Initialize >
   New Cluster**. Set the cluster domain to
   `technitium-cluster.infra.leehosanganson.dev` and the primary IP to
   `192.168.1.211`.
3. Log in to `technitium-2`, then use **Administration > Cluster > Initialize >
   Join Cluster**. Enter the primary node address `192.168.1.211` and the
   joining node's own address `192.168.1.212`. Provide the primary
   administrator credentials in the UI only.
4. Confirm both nodes appear in the cluster, the secondary synchronizes, and
   DNS answers on both addresses. Check DNS and cluster logs for TLS/DANE or
   zone-sync errors.

The cluster reconciler does not initialize or join nodes. It checks the local
cluster state on every run. It makes no API writes unless the cluster is
initialized, the reported cluster domain exactly matches the fixed identifier,
and the local node is explicitly reported as `Self` with role `Primary`. An
uninitialized, mismatched, secondary, unavailable, or unauthorized node fails
that run. The systemd timer tries again in five minutes. After promotion, the
new primary passes the same check and reconciles; the former primary stops
writing as soon as it is no longer reported as primary.

## Declarative DNS and block lists

The shared NixOS module owns the desired state through its non-secret
`homelab.technitium.clusterDomain`, `blockListUrls`, and `zones` options. It
serializes those values into a JSON file in the Nix store. The Python reconciler
reads that file at runtime; it contains no desired DNS data constants. The API
token remains external and is loaded only at runtime from the SOPS credential.

The primary reconciler sets only `enableBlocking=true` and the exact four
block-list URLs below. Other Technitium settings are not submitted to the
settings API and remain unchanged.

- Hagezi Pro: `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt`
- Hagezi Popup Ads: `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/popupads.txt`
- Hagezi Fake: `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/fake.txt`
- Hagezi NSFW: `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/nsfw.txt`

It also ensures that `home.lab` and `homelab.leehosanganson.dev` are Primary
zones and members of the auto-created catalog
`cluster-catalog.technitium-cluster.infra.leehosanganson.dev`. The module's
`zones` option declares the 18 `home.lab` host-to-address mappings and the apex
and wildcard A records in `homelab.leehosanganson.dev`; both latter records
point to `192.168.1.250`.

The reconciler adds missing address records with overwrite disabled. It does
not replace whole zones or delete records. Technitium does not provide a
reliable ownership marker for these records in this workflow, so an existing
record with a different address is retained and the desired address is added
beside it. Review such conflicts manually if an exact single-address answer is
required. Removing obsolete managed records is also a manual cleanup task.

Before any writes, reconciliation fails if a target zone is disabled, an exact
desired A record is disabled, or duplicate exact desired records make the
current state ambiguous. Enable the zone or record, or remove duplicate records
in Technitium, then let the timer retry.

## API credential setup

The reconciliation option is disabled by default and is not enabled on either
host until its external credential is configured. The credential value is not
stored in this repository or Nix. It is read at runtime from the external SOPS
secrets file configured for each host. Before enabling reconciliation for a
host, add the SOPS key `technitium-api-token` to the external `secrets.yaml`
used by the NixOS flake, then set
`homelab.technitium.reconciliation.enable = true;` in that host's NixOS
configuration. The value must be a Technitium API token, not an administrator
password. Do not put its value in a tracked file, Nix option, command argument,
environment variable, or URL.

Create the token through Technitium for a dedicated account with only the
permissions needed by the reconciler. The account needs Administration: View
(for cluster state), Settings: View and Modify, Zones: View and Modify, Zone:
View and Modify, and Zone: Delete (needed by the zone-options API). The token
is sent only in the HTTP `Authorization: Bearer` header. Systemd's
`LoadCredential` passes the SOPS-managed file to the process through its
credential directory; the program does not print it or include it in request
URLs.

The reconciler is safe to retry. It stays inactive until the SOPS key and
`reconciliation.enable` option are both configured. If cluster, settings, zone, or record checks fail during read-only preflight,
the run makes no changes. An invalid token or API outage at that stage also
fails before writes. A later connection or permission failure can occur after
an earlier API write; the timer retries, and each operation converges without
duplicating exact existing records. Successful runs only add or adjust the
desired settings, catalog membership, and missing records.

## Verification

Run the mocked API tests from the repository root:

```sh
python3 nixos/scripts/test_technitium_reconcile.py
```

They cover cluster and primary-role gates for both `nodes` and `clusterNodes`,
missing or malformed node data, API and authorization failures, exact
block-list settings and the state returned after a JSON settings write,
preservation of unrelated settings and DNS records, zone/catalog membership,
disabled-zone and disabled-record preflight, duplicate-record detection,
idempotence, and bearer-token handling. They do not connect to either server.

NixOS configurations can be evaluated and built without applying them from the
`nixos/` directory:

```sh
nix eval .#nixosConfigurations.technitium-1.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.technitium-2.config.system.build.toplevel.drvPath
nix build .#nixosConfigurations.technitium-1.config.system.build.toplevel --no-link
nix build .#nixosConfigurations.technitium-2.config.system.build.toplevel --no-link
```

These checks do not access live Technitium nodes, initialize or join the
cluster, or activate the configurations. To verify live DNS after a separately
authorized setup, query both resolver addresses for a selected `home.lab` name,
the `homelab.leehosanganson.dev` apex, and a subdomain wildcard match. Also
confirm in the Technitium console that both zones are catalog members and that
the blocking configuration contains exactly the four URLs above.

Technitium clustering is not client failover. Configure each DNS client with
both `192.168.1.211` and `192.168.1.212` in its resolver list, with the desired
per-client ordering. The time and conditions for trying a secondary resolver
are client-dependent; listing both addresses does not guarantee immediate
retry or failover. Do not change any clients as part of this work. There are no
subnet-based policy groups: all clients use the same DNS service policy.

## Recovery and change safety

The cluster has one primary node. If it is unavailable but unrecoverable,
Technitium provides a manual **Promote To Primary** action on a secondary node.
Promotion removes the old primary from the cluster; it is a recovery operation,
not automatic failover. Verify the old primary's state and plan how it will be
rejoined or rebuilt before promoting. Keep backups of any data that is not
replicated by cluster configuration, and validate zone state after recovery.

Do not run OpenTofu apply, provision these VMs, alter existing Pi-hole
configuration, or change client resolver settings as part of this work. VM
provisioning and NixOS installation follow the existing
[IaC runbooks](iac-terraform-opentofu-provisioning.md) and
[iac-nixos-configurations.md](iac-nixos-configurations.md) when separately
authorized.
