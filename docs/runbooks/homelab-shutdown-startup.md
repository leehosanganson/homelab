# Whole-Homelab Shutdown and Startup

Use this runbook for a planned shutdown and restart of the homelab. It is a
sequence and a set of safety gates, not proof of the live topology. Repository
configuration can be stale, and it does not describe every physical device,
Proxmox VE (PVE) role, or guest. Confirm the live inventory before acting.

This runbook does not authorize database recovery, destructive changes, or
changes to manifests. It does not give a PVE node order, Ceph procedure, HA
procedure, UPS sequence, or generic database shutdown command. If a required
live fact or approved procedure is unknown, **STOP** and resolve it first.

## Safety rules

- Confirm the maintenance window, impact, owner, and rollback/recovery contacts.
- Confirm the current shell, Kubernetes context, PVE cluster, host, and target
  before each command or power action. Use the read-only checks below first.
- Keep an out-of-band path to the equipment that does not depend on homelab DNS,
  HAProxy, or Kubernetes. Confirm credentials, console access, and a working
  management device/network before starting.
- Use graceful, guest-aware shutdown actions. Do not use PVE **Stop**, reset,
  power removal, or similar hard-stop actions as substitutes for a guest
  shutdown. If a guest does not shut down cleanly, **STOP**; do not force it off.
- Do not use `kubectl scale`, delete workloads, or other bypasses to make
  shutdown appear complete. A deliberate, one-agent-at-a-time evacuation with
  `kubectl drain` is allowed only after application writers/jobs have stopped
  and database shutdown procedures have completed, while the Kubernetes API
  and cluster quorum remain healthy. Before each drain, check PodDisruptionBudgets
  (PDBs), DaemonSet pods, and storage detach/unmount requirements; use an explicit
  context, target node, and timeout. Record the node's cordon/drain state and
  results. If eviction is blocked or any check is unclear, **STOP**; do not use
  `--force`, `--delete-emptydir-data`/`--delete-local-data`, or
  `--disable-eviction`. Never drain multiple nodes as a mass shortcut. Do not
  change Flux desired state or reconciliation state just to silence workloads.
- Do not treat automatic VM startup as confirmed. `docs/runbooks/iac-nixos-configurations.md`
  says VMs are left powered off, but `terraform/main.tf` sets both
  `on_boot = true` and `started = true` (and ignores changes to `started`).
  Confirm actual PVE settings and the intended behavior for every VM before
  shutdown and restart. Do not run OpenTofu to resolve this discrepancy.
- Treat every PVE, storage, database, and UPS action as an operator action that
  needs the live-approved procedure for that system.

## Repository facts and live-confirmation gates

These facts are confirmed in the repository; they do not prove the live state:

- The IaC VM inventory is in [`terraform/terraform.tfvars`](../../terraform/terraform.tfvars).
  Its current entries reference PVE nodes `pve01` through `pve04`; use that only
  as a comparison list, not as proof of the live PVE inventory. It is not a
  complete PVE/physical-device inventory.
- K3s server hosts use the HAProxy virtual IP as their server address, and
  HAProxy has K3s control-plane backends. See
  [`nixos/modules/k3s.nix`](../../nixos/modules/k3s.nix) and
  [`nixos/modules/haproxy.nix`](../../nixos/modules/haproxy.nix). HAProxy must
  therefore be available before K3s servers start relying on that address.
- K3s workloads use Synology CSI/iSCSI and NFS storage. The repository points
  these to `nas1.home.lab`; see [`nixos/modules/k3s.nix`](../../nixos/modules/k3s.nix)
  and [`kubernetes/infra/synology-csi/base/storageclass/`](../../kubernetes/infra/synology-csi/base/storageclass/).
  Confirm that the NAS and its exports/volumes are available before K3s workloads
  depend on them. The repository does **not** establish whether the NAS also
  provides PVE storage.
- Repository recovery/configuration indicates an etcd-backed K3s server cluster,
  and the existing IaC runbook treats etcd membership and quorum as important
  during recovery. See
  [`docs/runbooks/iac-terraform-opentofu-provisioning.md`](iac-terraform-opentofu-provisioning.md).
  Confirm the actual live datastore and membership, quorum, and approved
  whole-cluster shutdown and startup procedures before acting. Do not assume the
  live datastore, member count, or node order from this runbook.
- Flux manages infrastructure, monitoring, and application resources. The
  cluster recovery runbook shows these reconciliation groups and documents
  database recovery boundaries: [`docs/runbooks/cluster-recovery.md`](cluster-recovery.md).
  Confirm live Flux Kustomization and HelmRelease readiness and suspension state
  before acting. Do not suspend, resume, or force reconciliation as part of this
  runbook without a separate approved plan.
- CNPG (CloudNativePG) manages PostgreSQL clusters. The repository includes a
  CNPG 1.27.0 manifest, but the live operator version and correct shutdown
  procedure must be confirmed. Use the installed-version-specific CNPG
  procedure; do not guess at database commands or remove/scale resources.

Before proceeding, also confirm from the live PVE interface and approved
operational records:

- Which PVE nodes, guests, physical hosts, network devices, storage systems,
  and UPS-backed devices are in scope, including guests absent from IaC.
- Current PVE cluster status, storage configuration/health, quorum, HA-managed
  guests, and whether Ceph is present. Confirm the approved PVE shutdown and
  startup procedure for those exact roles. **Do not proceed on an unknown or
  unhealthy state.**
- Whether the NAS is independent hardware, a VM, or a PVE storage dependency;
  identify the required NAS shutdown/startup method. If this creates a dependency
  cycle or its role is unclear, **STOP**.
- Current VM `on_boot` and startup-order behavior in PVE, including any
  differences from `terraform/main.tf`; identify which services are expected to
  start automatically and which require an operator action.
- Current K3s server/member health and etcd quorum, storage/PVC health, Flux
  Kustomization and HelmRelease state, and the installed CNPG operator version.
- Out-of-band access and the site-specific UPS/network-power sequence. This
  repository contains no approved UPS sequence; follow the equipment
  manufacturer and local electrical/safety procedures.

## Preflight inventory (read-only)

Record the output and the operator-confirmed live inventory before shutdown.
These commands inspect state; they do not shut down or change resources. Confirm
that each CLI is configured for the intended environment before running it.

From the Kubernetes management host:

```sh
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A
kubectl get pvc -A
kubectl get clusters.postgresql.cnpg.io -A
flux get kustomizations -A
flux get helmreleases -A
```

From an approved shell on a healthy PVE node, and on other nodes where the
local procedure requires it (skip a feature-specific check only after confirming
that feature is not configured):

```sh
pvesh get /cluster/status
pvesh get /cluster/resources --type vm
pvecm status
pvesm status
ha-manager status
ceph -s
```

Do not interpret a failed or missing command as proof that a feature is absent.
Check the PVE configuration and operational records. Do not continue if cluster
quorum, storage health, HA state, Ceph state, NAS role, VM state, or inventory
cannot be established.

Use this table as the **live** inventory; complete it rather than assuming the
repository list is complete:

| System / guest                         | Live host / role | Depends on / serves | Shutdown method and source | Startup method and source | Confirmed |
| -------------------------------------- | ---------------- | ------------------- | -------------------------- | ------------------------- | --------- |
| Network, router, switches, access path |                  |                     |                            |                           |           |
| DNS resolvers                          |                  |                     |                            |                           |           |
| NAS / storage                          |                  |                     |                            |                           |           |
| PVE nodes / cluster services           |                  |                     |                            |                           |           |
| HAProxy guests / VIP                   |                  |                     |                            |                           |           |
| K3s servers and agents                 |                  |                     |                            |                           |           |
| CNPG databases and applications        |                  |                     |                            |                           |           |
| Other guests / physical systems / UPS  |                  |                     |                            |                           |           |

**Preflight go/no-go:** proceed only when the live inventory is complete for the
requested scope, every dependency has a verified procedure, backups meet the
operator's requirements, and all health/quorum/storage/HA gates above pass. If
any item is unknown, unhealthy, or inconsistent with the expected state, **STOP**.

## Planned shutdown

Keep a log of each phase, target, result, and time. If the sequence is
interrupted, repeat the read-only checks and continue from verified live state;
do not repeat a power action blindly. Do not skip a phase because a service
appears idle. The sequence below preserves dependencies where the repository
establishes them; live PVE, NAS, and cluster rules take precedence.

1. **Quiesce and stop applications.** Notify users, stop external jobs and
   write-producing clients, then gracefully stop application workloads through
   each application's approved procedure. Confirm that active Flux reconciliation
   will not undo that procedure. Do not use generic scale/delete operations or
   suspend Flux as a shortcut; any needed Flux change requires a separate
   approved plan. Confirm backups and any required final data checks. If no
   approved application stop procedure exists, **STOP** before touching its
   database.
2. **Shut down databases by their supported procedure.** Confirm the running
   CNPG operator version and follow its matching shutdown guidance. Verify the
   expected database/cluster state after the procedure. Do not issue a guessed
   `kubectl`, SQL, container, or systemd shutdown command. If the installed
   version's procedure is unavailable or the result is unclear, **STOP**.
3. **Stop Kubernetes workloads and cluster through the approved process.**
   Confirm Flux state and follow the live K3s shutdown procedure for the
   confirmed datastore and member topology. Preserve quorum until that procedure
   says the cluster can be stopped; do not invent an order or power off a subset
   of server members based on this document. After application writers/jobs have
   stopped and database procedures have completed, an agent may be evacuated
   with `kubectl drain` one node at a time only while the API and quorum remain
   healthy. Before each drain, check PDBs, DaemonSet pods, and storage
   detach/unmount requirements; use an explicit context, target node, and
   timeout, then record the cordon/drain state and result. If a drain is blocked
   or a check is unclear, **STOP**. Never use `--force`,
   `--delete-emptydir-data`/`--delete-local-data`, or `--disable-eviction`; do
   not drain server nodes or use drains as a mass shortcut. Shut down K3s guests
   gracefully only after the workload, database, storage, and quorum gates
   pass.
4. **Shut down remaining service guests.** Keep DNS and HAProxy available until
   they are no longer needed for user access, name resolution, or management.
   After K3s no longer depends on HAProxy, use the confirmed VM inventory and
   guest procedures to shut down HAProxy, DNS, and other guests. Confirm each
   guest is off cleanly. This is not a PVE node order.
5. **Resolve the NAS/PVE shutdown dependency.** Keep NAS/storage online until
   every dependent K3s/PVE guest is stopped. If the NAS is a PVE guest, gracefully
   stop it after its dependents stop and before shutting down its PVE host. If
   the NAS provides PVE storage, follow the approved storage-specific PVE
   procedure for the exact NAS/host order; do not infer whether NAS or PVE stops
   first. If the role or approved order is unknown, **STOP**.
6. **Shut down PVE only after the guests and storage gates pass.** Use the
   approved procedure for the live PVE cluster, including its quorum, HA, and
   storage/Ceph rules. Confirm all guests and any NAS/PVE storage prerequisites
   are in the state required by the approved procedure. Do not power off PVE
   nodes in a guessed order.
7. **Shut down remaining independent NAS, network, and UPS-backed equipment
   only in the confirmed order.** If independent NAS hardware does not provide
   PVE storage, stop it only after all dependent services no longer need it.
   Keep required network access until all dependent hosts are off. This runbook
   does not define UPS or electrical sequencing; follow approved site and
   equipment procedures.
8. **Confirm the end state.** Compare live equipment status against the
   inventory. Record intentional exceptions, remaining powered devices, and
   any warnings. Do not report a complete shutdown if a target is merely
   unreachable.

## Startup

Use the same confirmed inventory. Do not assume PVE auto-start settings are
correct, and do not start all guests at once. After each phase, verify its gate
before proceeding.

1. **Restore physical power and the management path.** Follow approved
   site/equipment UPS and electrical procedures; this runbook does not define
   device sequencing. Restore network, router, switches, and the management
   path according to the confirmed site sequence. Verify the out-of-band path
   still works. Do not assume DNS guests are available yet; use confirmed
   direct addresses until their PVE guests are started.
2. **Start independent storage dependencies.** If the NAS is independent
   hardware, start it using its confirmed procedure and verify required exports,
   volumes, and reachability before dependent PVE storage or K3s workloads start.
   If it is a PVE guest, do not assume it can start before PVE; use the approved
   design in the next phase. If PVE itself depends on storage that is not yet
   available, or the dependency is unclear, **STOP**.
3. **Start the PVE cluster and NAS guest if applicable.** Follow the
   live-approved PVE startup procedure; verify cluster quorum, storage health,
   HA/Ceph state (where configured), and node status. If the NAS is a PVE guest,
   start it only through the confirmed guest procedure, then verify its required
   exports/volumes before starting any dependent guests. Do not rely on automatic
   VM startup until its live behavior has been checked. If PVE or NAS does not
   reach its expected healthy state, **STOP** before starting dependent guests.
4. **Start the required DNS and HAProxy guests.** Use the confirmed inventory
   and locally approved order; this runbook does not assume a DNS/HAProxy order.
   Before starting K3s servers, verify the needed name resolution and the
   HAProxy VIP/service. Repository K3s server configuration points to the
   HAProxy VIP. A backend may be unavailable while K3s is off; verify the
   gateway itself is healthy and do not treat backend health as proof of cluster
   health.
5. **Start K3s servers and agents by the live cluster procedure.** Confirm
   etcd member state and quorum using the approved procedure. Start server
   members in the operator-approved order, verify the API and quorum, then
   start agents as directed by the same procedure. The repository does not
   define the live member count or a safe member-by-member order. If quorum or
   membership is uncertain, **STOP** and use
   [`docs/runbooks/iac-terraform-opentofu-provisioning.md`](iac-terraform-opentofu-provisioning.md)
   for its documented K3s member diagnostics; do not remove members or change
   cluster state as part of startup.
6. **Verify storage and Flux before applications.** Confirm K3s nodes are
   `Ready`, required storage classes/PVCs are healthy, and Synology/NFS-backed
   volumes are available. Inspect Flux Kustomization and HelmRelease status and
   confirm the expected reconciliation/suspension state. Do not force resume,
   suspend, or reconcile resources without an approved plan. If resources are
   unhealthy or reconciliation is unexpected, **STOP** and diagnose before
   progressing.
7. **Verify databases and applications.** Confirm CNPG's installed version
   and cluster health using read-only status checks. Follow the installed
   version's procedure for any required database action. Validate critical
   application readiness and user-facing workflows, data availability, DNS,
   and ingress. Use the dedicated
   [`cluster-recovery.md`](cluster-recovery.md) runbook only if this becomes a
   data-recovery event; do not treat ordinary startup as recovery.
8. **Declare success only after checks pass.** Confirm each critical service
   through its real access path, verify expected recent data, and record any
   outstanding exceptions and owner. A running VM, ready pod, healthy CNPG
   status, or green Flux status alone is not proof that the whole service works.

## Stop and recovery gates

Stop the sequence and do not improvise if:

- Live PVE topology, quorum, storage, HA, Ceph, VM auto-start, or guest inventory
  is unknown or differs from the planned inventory.
- NAS role or storage dependencies are unknown, or the NAS/PVE shutdown or
  startup order cannot be determined safely.
- Out-of-band access, credentials, or the approved UPS/electrical procedure is
  unavailable.
- K3s etcd member state/quorum is unhealthy or unknown, or a server would be
  stopped/started outside the approved cluster procedure.
- Flux Kustomization/HelmRelease status or suspension state is unexpected.
- CNPG version-specific shutdown guidance is missing, or database status is
  uncertain.
- A guest does not shut down cleanly, a storage check fails, or a startup
  health gate does not pass.

For PVE cluster, HA, storage, or VM provisioning issues, use the applicable
PVE/IaC operational documentation, including
[`iac-terraform-opentofu-provisioning.md`](iac-terraform-opentofu-provisioning.md)
and [`iac-nixos-configurations.md`](iac-nixos-configurations.md). For a K3s
cluster that cannot regain quorum, follow the documented K3s diagnostics and
approved recovery process; this document does not authorize etcd member
removal. For Kubernetes data loss or restore, use
[`cluster-recovery.md`](cluster-recovery.md). Do not power-cycle, force-stop,
reinstall, delete, or restore resources as an improvised recovery action.

## Quick checklist

### Before

- [ ] Maintenance window, impact, owner, and recovery contacts confirmed.
- [ ] Out-of-band access and independent management path tested.
- [ ] Live inventory completed; repository inventory reconciled against PVE.
- [ ] PVE quorum/storage/HA/Ceph and VM auto-start behavior confirmed.
- [ ] NAS role and dependencies confirmed; NAS/PVE shutdown and startup order documented.
- [ ] K3s member/quorum, PVC, Flux, HelmRelease, and CNPG version/status captured.
- [ ] App data safeguards and system-specific shutdown procedures confirmed.
- [ ] UPS and network-power sequence confirmed from approved local guidance.

### Shutdown

- [ ] New application writes/jobs stopped through approved procedures.
- [ ] Databases stopped using the installed-version-specific CNPG procedure.
- [ ] K3s stopped through the live quorum-safe procedure; any agent drain was one node at a time after writers/jobs and database procedures completed, with API/quorum healthy, PDB/DaemonSet/storage checks passed, explicit context/target/timeout used, and cordon/drain state recorded. Stop on blockage; no force, local-data deletion, eviction bypass, server-node drain, or mass drain.
- [ ] Remaining guests shut down gracefully and verified off.
- [ ] PVE stopped only after approved cluster/storage/HA gates pass.
- [ ] NAS, network, and UPS-backed equipment stopped only in confirmed order.
- [ ] Final equipment state and exceptions recorded.

### Startup

- [ ] Network and management path available; DNS verified or direct addresses used.
- [ ] NAS/storage healthy before dependent services.
- [ ] PVE quorum, storage, HA/Ceph state healthy before dependent guests.
- [ ] DNS/HAProxy gateway healthy before K3s servers rely on the VIP.
- [ ] K3s etcd quorum/API healthy before agents and workloads progress.
- [ ] Storage, Flux/HelmRelease, and CNPG status verified.
- [ ] Critical apps, data, DNS, ingress, and real user workflows validated.
- [ ] Results, exceptions, and completion owner recorded.
