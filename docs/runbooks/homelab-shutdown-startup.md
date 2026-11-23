# Whole-Homelab Shutdown and Startup

Use this runbook for a planned shutdown and restart of the homelab. It is a sequence and a set of safety gates, not proof of the live topology. Repository configuration can be stale, and it does not describe every physical device, Proxmox VE (PVE) role, or guest. Confirm the live inventory before acting.

This runbook does not authorize database recovery, destructive changes, or changes to manifests. It does not give a PVE node order, Ceph procedure, HA procedure, UPS sequence, or generic database shutdown command. If a required live fact or approved procedure is unknown, **STOP** and resolve it first.

## Safety rules

- Confirm the maintenance window, impact, owner, and rollback/recovery contacts.
- Confirm the current shell, Kubernetes context, PVE cluster, host, and target before each command or power action. Use the read-only checks below first.
- Keep an out-of-band path to the equipment that does not depend on homelab DNS, HAProxy, or Kubernetes. Confirm credentials, console access, and a working management device/network before starting.
- Use graceful, guest-aware shutdown actions. Do not use PVE **Stop**, reset, power removal, or similar hard-stop actions as substitutes for a guest shutdown. If a guest does not shut down cleanly, **STOP**; do not force it off.
- Do not use `kubectl scale`, delete workloads, or other bypasses to make shutdown appear complete. For a full-cluster outage, drain is optional after writers/jobs and databases are safely quiesced and the approved K3s procedure permits per-guest shutdown. For rolling maintenance, drain one worker only after the database procedure completes and the live K3s procedure permits it with API and quorum healthy; check PDBs, DaemonSet pods, and storage detach/unmount first. If blocked or unclear, stop this branch and resolve it under an owner-approved procedure. Never use `--force`, `--delete-emptydir-data`, or `--disable-eviction`, drain a server or multiple nodes, or change Flux state to silence workloads. PDBs constrain eviction requests such as drain, not guest poweroff.
- VM auto-start is unconfirmed: [`iac-nixos-configurations.md`](iac-nixos-configurations.md) says VMs are left off, but `terraform/main.tf` sets `on_boot = true` and `started = true` (and ignores changes to `started`). Verify live PVE settings and intended behavior for every VM; do not run OpenTofu to resolve the discrepancy.
- Use each system's live-approved procedure for PVE, storage, database, and UPS actions.

## Repository facts and live-confirmation gates

These facts are confirmed in the repository; they do not prove the live state:

- The IaC VM inventory is in [`terraform/terraform.tfvars`](../../terraform/terraform.tfvars). Its current entries reference PVE nodes `pve01` through `pve04`; use that only as a comparison list, not as proof of the live PVE inventory. It is not a complete PVE/physical-device inventory.
- K3s server hosts use the HAProxy virtual IP as their server address, and HAProxy has K3s control-plane backends. See [`nixos/modules/k3s.nix`](../../nixos/modules/k3s.nix) and [`nixos/modules/haproxy.nix`](../../nixos/modules/haproxy.nix). HAProxy must therefore be available before K3s servers start relying on that address.
- K3s workloads use Synology CSI/iSCSI and NFS storage. The repository points these to `nas1.home.lab`; see [`nixos/modules/k3s.nix`](../../nixos/modules/k3s.nix) and [`kubernetes/infra/synology-csi/base/storageclass/`](../../kubernetes/infra/synology-csi/base/storageclass/). Confirm that the NAS and its exports/volumes are available before K3s workloads depend on them. The repository does **not** establish whether the NAS also provides PVE storage.
- Repository recovery/configuration indicates an etcd-backed K3s server cluster; the [IaC runbook](iac-terraform-opentofu-provisioning.md) also treats membership and quorum as critical. Confirm the live datastore, members, quorum, and approved shutdown/startup procedures. Do not infer the live datastore, member count, or node order here.
- Flux manages infrastructure, monitoring, and application resources. The production Kustomization definitions are in [`fluxcd/clusters/production/infra.yaml`](../../fluxcd/clusters/production/infra.yaml), [`monitoring.yaml`](../../fluxcd/clusters/production/monitoring.yaml), and [`apps.yaml`](../../fluxcd/clusters/production/apps.yaml). The cluster recovery runbook documents database recovery boundaries: [`docs/runbooks/cluster-recovery.md`](cluster-recovery.md). Confirm live Flux Kustomization and HelmRelease readiness and suspension state before acting. Do not suspend, resume, or force reconciliation as part of this runbook without a separate approved plan.
- CNPG (CloudNativePG) manages PostgreSQL clusters. The repository includes a [CNPG 1.27.0 manifest](../../kubernetes/infra/cloudnativepg/cnpg-1.27.0.yaml), but the live operator version and its supported shutdown method are unknown. **STOP:** confirm both from the installed operator and matching procedure before database or K3s shutdown. There is no generic CNPG shutdown command; do not guess commands or remove/scale resources.

Before proceeding, confirm from the live PVE interface and approved records:

- In-scope PVE nodes, guests (including those absent from IaC), physical hosts, network devices, storage, and UPS-backed devices.
- PVE cluster status, storage health, quorum, HA-managed guests, Ceph presence, and the approved shutdown/startup procedure for these roles. **STOP** on unknown or unhealthy state.
- NAS role (independent hardware, VM, or PVE storage dependency) and its procedures. **STOP** if its role is unclear or creates a dependency cycle.
- Live VM `on_boot` and startup-order behavior, differences from `terraform/main.tf`, and which services need operator action.
- K3s member health and etcd quorum, storage/PVC health, Flux Kustomization/HelmRelease state, and installed CNPG version.
- Working out-of-band access and the site UPS/network-power sequence. No UPS sequence is approved here; follow manufacturer and local electrical/safety procedures.

## Preflight inventory (read-only)

Record these read-only results and the confirmed live inventory.

From the Kubernetes management host, confirm the current Kubernetes context before running the remaining checks:

```sh
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods --all-namespaces -o wide
kubectl get pvc --all-namespaces
kubectl get pdb --all-namespaces
kubectl get clusters.postgresql.cnpg.io --all-namespaces
kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{range .items[*]}{.metadata.name}{" phase="}{.status.phase}{" "}{range .status.containerStatuses[*]}{.name}{" ready="}{.ready}{" image="}{.image}{" imageID="}{.imageID}{"\n"}{end}{end}'
flux get kustomizations --all-namespaces
flux get helmreleases --all-namespaces
```

The command queries the repository's `cnpg-system` controller label and prints pod phase, container status, image, and image ID. A Running, ready controller image is only an identification clue: confirm the installed version and matching procedure. If no pod matches, find the live namespace/controller and query its image; do not infer the version from the repository manifest.

From an approved management shell, connect to a **verified live PVE node**. Run applicable checks only on a healthy node; use PVE configuration and operator records to establish whether HA or Ceph is configured:

```sh
PVE_NODE='<verified-live-pve-node>'
ssh "root@$PVE_NODE" 'pvesh get /cluster/status'
ssh "root@$PVE_NODE" 'pvesh get /cluster/resources --type vm'
ssh "root@$PVE_NODE" 'pvecm status'
ssh "root@$PVE_NODE" 'pvesm status'
ssh "root@$PVE_NODE" 'ha-manager status'  # only if HA is configured
ssh "root@$PVE_NODE" 'ceph -s'            # only if Ceph is configured
```

A failed or missing command does not prove a feature is absent. Check PVE configuration and records; **STOP** if quorum, storage, HA/Ceph state, NAS role, VM state, or inventory is unknown.

### Committed VM reference (stale-prone; not live inventory)

Names, VM IDs, and PVE placements below come from [`terraform/terraform.tfvars`](../../terraform/terraform.tfvars); corresponding NixOS definitions are under [`nixos/hosts/`](../../nixos/hosts/). This stale-prone, incomplete repo list is for comparison only: verify each ID and current owner in live PVE, and inventory guests/physical hosts not listed here.

| VM name         | VM ID | PVE node (repo reference) |
| --------------- | ----: | ------------------------- |
| `pihole-1`      |   102 | `pve01`                   |
| `pihole-2`      |   103 | `pve04`                   |
| `k3s-ctrl-04`   |   104 | `pve04`                   |
| `k3s-work-01`   |   105 | `pve04`                   |
| `k3s-work-02`   |   106 | `pve04`                   |
| `k3s-work-03`   |   107 | `pve01`                   |
| `k3s-ctrl-01`   |   108 | `pve01`                   |
| `k3s-ctrl-02`   |   109 | `pve02`                   |
| `k3s-work-04`   |   110 | `pve02`                   |
| `haproxy-1`     |   201 | `pve01`                   |
| `haproxy-2`     |   202 | `pve04`                   |
| `haproxy-3`     |   203 | `pve03`                   |
| `technitium-1`  |   211 | `pve01`                   |
| `technitium-2`  |   212 | `pve04`                   |
| `matter-server` |   302 | `pve01`                   |
| `hermes-agent`  |   303 | `pve01`                   |

Use the following blank table as the **live** inventory; complete it rather than assuming the repository list is complete:

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

**Preflight go/no-go:** proceed only with a complete live inventory, verified dependency procedures, operator-approved backups, and all health/quorum/storage/HA gates passed. **STOP** on any unknown, unhealthy, or unexpected state.

## Planned shutdown

Log each phase, target, result, and time. If interrupted, repeat read-only checks and resume from verified state; never repeat a power action blindly or skip a phase because a service appears idle. Live PVE, NAS, and cluster procedures take precedence over the sequence below.

1. **Quiesce and stop applications.** Notify users; stop external jobs and write-producing clients, then gracefully stop workloads using each application's approved procedure. Confirm active Flux will not undo it; do not scale/delete workloads or suspend Flux as a shortcut. Confirm backups and required final data checks. **STOP** before database shutdown if no approved application procedure exists.
2. **Shut down databases by their supported procedure.** After the CNPG version/method gate above passes, follow that version's guidance and verify the expected database state. **STOP** if guidance is unavailable or the result unclear; do not guess a `kubectl`, SQL, container, or systemd command.
3. **Stop Kubernetes workloads and cluster through the approved process.** Confirm Flux state and follow the approved live K3s procedure for the verified datastore and member topology. Preserve quorum and use its exact member order; this runbook does not authorize stopping a server subset or inventing an order.

   **Full-cluster outage:** drain is optional; it evacuates a node while the cluster runs, and PDBs constrain eviction requests, not guest poweroff. Guest shutdown does not ensure graceful app/database shutdown, and the repository's [K3s configuration](../../nixos/modules/k3s.nix) does not explicitly set kubelet graceful-shutdown grace periods. Do not assume kubelet shutdown handling is configured. After writers/jobs and stateful databases are safely quiesced under owner/version-specific procedures and the CNPG gate passes, follow the approved K3s/etcd member/quorum order; skip worker drains only if that procedure allows it.

   **Optional drain branch — rolling maintenance:** while the cluster runs, drain one verified worker only after writers/jobs and the installed-version-specific database shutdown are complete, storage checks pass, and the live K3s procedure permits it with API and quorum healthy. Check PDBs, DaemonSet pods, and affected volume detach/unmount first. Confirm `$NODE` is a worker, not a server:

   ```sh
   NODE='<verified-worker-node-name>'
   kubectl get pdb --all-namespaces
   kubectl get daemonsets --all-namespaces
   kubectl get pods --all-namespaces -o wide --field-selector "spec.nodeName=$NODE"
   kubectl get pvc --all-namespaces
   kubectl get pv
   ```

   **STOP / REVIEW:** inspect all check output. Confirm `$NODE` is the exact live worker to drain, API and quorum are healthy, each affected volume can detach, and the approved K3s procedure authorizes this action. Run only the separate drain command below; never paste or run the check and action blocks as a batch.

   ```sh
   kubectl drain "$NODE" --ignore-daemonsets --timeout=10m
   ```

   **STOP:** if drain is blocked or times out, do not force it or try another worker. Resolve the block under an owner-approved procedure, or skip drain for a full-cluster outage only when its gates pass. After a successful drain, check its status separately:

   ```sh
   kubectl get node "$NODE" -o wide
   ```

   After drain, follow the live K3s member procedure. Phase 4's SSH poweroff is for an individually verified guest, not a substitute for member ordering.

4. **Shut down guests one at a time, excluding the NAS VM and other storage dependencies.** Keep DNS and HAProxy until no longer needed for access or management. Verify each guest's live identity and relevant services. For K3s guests, proceed only after writers/jobs and databases are safely quiesced, the CNPG version-specific gate passes, and the live member/quorum procedure permits this guest. Drain is not required for a full-cluster outage. Set the exact live guest values and inspect these read-only checks:

   ```sh
   PVE_NODE='<verified-live-owning-pve-node>'
   VMID='<verified-live-vm-id>'
   GUEST='root@<verified-guest-address>'
   case "$VMID" in
     ''|*[!0-9]*) echo 'Replace VMID with the verified numeric VM ID.' >&2; exit 1 ;;
   esac
   ssh "root@$PVE_NODE" "qm status $VMID"
   ssh "$GUEST" 'systemctl is-system-running'
   # On a K3s guest only; otherwise check its relevant service/unit.
   ssh "$GUEST" 'systemctl status k3s'
   ```

   **STOP / REVIEW:** inspect the output. Confirm the exact live guest ID, address, owning PVE host, running state, and authorization for shutdown. Choose one shutdown method only. Do not paste or run the check and action blocks as a batch. For guest-side shutdown, deliberately run only:

   ```sh
   ssh "$GUEST" 'systemctl poweroff'
   ```

   Then verify the guest state in a separate check:

   ```sh
   ssh "root@$PVE_NODE" "qm status $VMID"
   ```

   Confirm the result is `stopped` before proceeding. If the command times out, the guest remains running, or the result is unclear, **STOP**. Do not force it off or switch methods without its approved procedure.

   A verified guest may instead be shut down through its current owning PVE node, one VM at a time. Use the status command from the read-only check block above; do not run both shutdown methods. **STOP / REVIEW:** inspect that output and confirm the exact guest ID, owning PVE host, `running` state, all shutdown gates, and authorization. Then deliberately run only this action command, not the checks and action as a batch:

   ```sh
   ssh "root@$PVE_NODE" "qm shutdown $VMID --timeout 300"
   ```

   **STOP:** if the command times out, the guest does not shut down cleanly, or the result is unclear, do not run `qm stop`, a force-stop, `qm stopall`, `qm startall`, or `pvenode stopall`. After a successful command, verify in a separate read-only check:

   ```sh
   ssh "root@$PVE_NODE" "qm status $VMID"
   ```

   Confirm the result is `stopped` before moving on. The committed table above is not sufficient to authorize a target. This is not a PVE node order.

5. **Resolve the NAS/PVE shutdown dependency.** Keep NAS/storage online until dependents stop. If the NAS is a PVE guest, gracefully stop it only after dependents stop and the approved order for its role/host is confirmed. If it provides PVE storage, follow the storage-specific procedure; do not infer whether NAS or PVE stops first. **STOP** if the role, dependent state, or order is unknown.
6. **Shut down PVE only after the guests and storage gates pass.** This is a separate, live-approved PVE operation, not a command sequence inferred from this runbook. Before each host action, confirm the approved quorum, storage, HA, and Ceph procedure and that its exact prerequisites pass. There is no fixed host order here. Only when the live operator's approved procedure explicitly permits the specific host to shut down, the command template is:

   ```sh
   ssh root@'<verified-pve-host>' 'shutdown -h now'
   ```

   Do not run it based on this document alone. Starting a PVE host must use the approved out-of-band/physical procedure; this runbook provides no generic remote CLI start command. Never use `pvenode stopall`, `qm stop`, force-stop, mass scripts, or OpenTofu for shutdown/startup.

7. **Shut down remaining independent NAS, network, and UPS-backed equipment only in the confirmed order.** If independent NAS hardware does not provide PVE storage, stop it only after all dependent services no longer need it. Keep required network access until all dependent hosts are off. This runbook does not define UPS or electrical sequencing; follow approved site and equipment procedures.
8. **Confirm the end state.** Compare live equipment status against the inventory. Record intentional exceptions, remaining powered devices, and any warnings. Do not report a complete shutdown if a target is merely unreachable.

## Startup

Use the same confirmed inventory. Do not assume PVE auto-start settings are correct, and do not start all guests at once. After each phase, verify its gate before proceeding.

1. **Restore physical power and the management path.** Follow approved site/equipment UPS and electrical procedures; this runbook does not define device sequencing. Restore network, router, switches, and the management path according to the confirmed site sequence. Verify the out-of-band path still works. Do not assume DNS guests are available yet; use confirmed direct addresses until their PVE guests are started.
2. **Start independent storage dependencies.** If the NAS is independent hardware, start it using its confirmed procedure and verify required exports, volumes, and reachability before dependent PVE storage or K3s workloads start. If it is a PVE guest, do not assume it can start before PVE; use the approved design in the next phase. If PVE itself depends on storage that is not yet available, or the dependency is unclear, **STOP**.
3. **Start the PVE cluster and NAS guest if applicable.** Follow the live-approved PVE startup procedure; verify cluster quorum, storage health, HA/Ceph state (where configured), and node status. If the NAS is a PVE guest, start it only through the confirmed guest procedure, then verify its required exports/volumes before starting any dependent guests. Do not rely on automatic VM startup until its live behavior has been checked. If PVE or NAS does not reach its expected healthy state, **STOP** before starting dependent guests. Starting a powered-off PVE host requires the approved out-of-band/physical procedure; this runbook gives no generic CLI start command.
4. **Start the required DNS and HAProxy guests.** Use the confirmed inventory and locally approved order; this runbook does not assume a DNS/HAProxy order. Before starting K3s servers, verify the needed name resolution and the HAProxy VIP/service. Repository K3s server configuration points to the HAProxy VIP. A backend may be unavailable while K3s is off; verify the gateway itself is healthy and do not treat backend health as proof of cluster health. For each guest, set its verified PVE node and VM ID, then check state:

   ```sh
   PVE_NODE='<verified-live-owning-pve-node>'
   VMID='<verified-live-vm-id>'
   case "$VMID" in
     ''|*[!0-9]*) echo 'Replace VMID with the verified numeric VM ID.' >&2; exit 1 ;;
   esac
   ssh "root@$PVE_NODE" "qm status $VMID"
   ```

   **STOP / REVIEW:** inspect the output. Confirm the exact live guest ID, owning PVE host, `stopped` state, dependency gates, and authorization to start this guest. Deliberately run only the separate action command below. Never paste or run check and action as a batch.

   ```sh
   ssh "root@$PVE_NODE" "qm start $VMID"
   ```

   After the action completes, verify the result in a separate check:

   ```sh
   ssh "root@$PVE_NODE" "qm status $VMID"
   ```

   Confirm the result is `running` before proceeding. If it is not, **STOP**; do not repeat or broaden the action without the approved procedure. Use the same individually scoped template for K3s guests only at the point allowed by the approved member procedure in the next step. Never bulk-start guests.

5. **Start K3s servers and agents by the live cluster procedure.** Confirm etcd member state and quorum using the approved procedure. Start server members in the operator-approved order, verify the API and quorum, then start agents as directed by the same procedure. The repository does not define the live member count or a safe member-by-member order. If quorum or membership is uncertain, **STOP** and use [`docs/runbooks/iac-terraform-opentofu-provisioning.md`](iac-terraform-opentofu-provisioning.md) for its documented K3s member diagnostics; do not remove members or change cluster state as part of startup.
6. **Verify nodes, storage, Flux, and guests before applications.** Confirm the current Kubernetes context. After the live K3s procedure says the API is available, wait for nodes to become Ready and inspect nodes, workloads, volumes, and CNPG. Then inspect Flux status. These are read-only checks:

   ```sh
   kubectl wait --for=condition=Ready nodes --all --timeout=10m
   kubectl get nodes -o wide
   kubectl get pods --all-namespaces -o wide
   kubectl get pvc --all-namespaces
   kubectl get clusters.postgresql.cnpg.io --all-namespaces
   kubectl get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{range .items[*]}{.metadata.name}{" phase="}{.status.phase}{" "}{range .status.containerStatuses[*]}{.name}{" ready="}{.ready}{" image="}{.image}{" imageID="}{.imageID}{"\n"}{end}{end}'
   flux get kustomizations --all-namespaces
   flux get helmreleases --all-namespaces
   ```

   If a worker was drained for this shutdown, uncordon only after that specific node is back and Ready and the approved cluster procedure permits workloads to return to it:

   ```sh
   NODE='<verified-worker-node-name>'
   kubectl wait --for=condition=Ready "node/$NODE" --timeout=10m
   kubectl get node "$NODE" -o wide
   ```

   **STOP / REVIEW:** inspect the output and confirm this is the exact worker drained for this shutdown, it is Ready, and the approved cluster procedure permits it to receive workloads. Run only the separate action below; never paste or run the checks and action as a batch.

   ```sh
   kubectl uncordon "$NODE"
   ```

   Check PVE again from a verified live node; these do not replace the approved quorum/storage/HA/Ceph gate:

   ```sh
   PVE_NODE='<verified-live-pve-node>'
   ssh "root@$PVE_NODE" 'pvecm status'
   ssh "root@$PVE_NODE" 'pvesm status'
   ssh "root@$PVE_NODE" 'ha-manager status'  # only if HA is configured
   ssh "root@$PVE_NODE" 'ceph -s'            # only if Ceph is configured
   ```

   Never bulk-start guests; do not use `qm startall`. If nodes, storage, CNPG, Flux, PVE, or any guest state is unhealthy or unexpected, **STOP**. Do not make a Flux suspend/resume or reconcile action a standard step; it requires a separate approved plan and its own verification. If Flux is unexpectedly suspended, stop and resolve the state through that plan rather than silently changing it.

7. **Verify databases and applications.** Confirm CNPG's installed version and cluster health using read-only status checks. Follow the installed version's procedure for any required database action. Validate critical application readiness and user-facing workflows, data availability, DNS, and ingress. Use the dedicated [`cluster-recovery.md`](cluster-recovery.md) runbook only if this becomes a data-recovery event; do not treat ordinary startup as recovery.
8. **Declare success only after checks pass.** Confirm each critical service through its real access path, verify expected recent data, and record any outstanding exceptions and owner. A running VM, ready pod, healthy CNPG status, or green Flux status alone is not proof that the whole service works.

## Stop and recovery gates

Stop and do not improvise if any live inventory, PVE quorum/storage/HA/Ceph, VM auto-start, NAS dependency/order, out-of-band access, or UPS/electrical procedure is unknown; K3s membership/quorum or Flux state is unexpected; CNPG version-specific guidance or database state is uncertain; a guest fails to shut down cleanly; or any storage/startup health gate fails.

For PVE cluster, HA, storage, or VM provisioning issues, use the applicable PVE/IaC operational documentation, including [`iac-terraform-opentofu-provisioning.md`](iac-terraform-opentofu-provisioning.md) and [`iac-nixos-configurations.md`](iac-nixos-configurations.md). For a K3s cluster that cannot regain quorum, follow the documented K3s diagnostics and approved recovery process; this document does not authorize etcd member removal. For Kubernetes data loss or restore, use [`cluster-recovery.md`](cluster-recovery.md). Do not power-cycle, force-stop, reinstall, delete, or restore resources as an improvised recovery action.

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
- [ ] K3s stopped in the approved live member/quorum order. Full-outage drain is optional only after writers/jobs and databases are safely quiesced and the procedure permits per-guest shutdown. For rolling maintenance, drain one worker only after app/database procedures and PDB/DaemonSet/storage checks pass with API/quorum healthy; if blocked, stop and resolve under an owner-approved procedure. No force, local-data deletion, eviction bypass, server drain, or mass drain.
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
