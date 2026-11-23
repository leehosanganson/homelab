# Whole-Homelab Shutdown and Startup

Use this runbook for a planned shutdown and restart of the homelab. It is a sequence and a set of safety gates, not proof of the live topology. Repository configuration can be stale, and it does not describe every physical device, Proxmox VE (PVE) role, or guest. Confirm the live inventory before acting.

This runbook does not authorize database recovery, destructive changes, or changes to manifests. It does not give a PVE node order, Ceph procedure, HA procedure, UPS sequence, or generic database shutdown command. If a required live fact or approved procedure is unknown, **STOP** and resolve it first.

## Safety rules

- Confirm the maintenance window, impact, owner, and rollback/recovery contacts.
- Confirm the current shell, Kubernetes context, PVE cluster, host, and target before each command or power action. Use the read-only checks below first.
- Keep an out-of-band path to the equipment that does not depend on homelab DNS, HAProxy, or Kubernetes. Confirm credentials, console access, and a working management device/network before starting.
- Use graceful, guest-aware shutdown actions. Do not use PVE **Stop**, reset, power removal, or similar hard-stop actions as substitutes for a guest shutdown. If a guest does not shut down cleanly, **STOP**; do not force it off.
- Do not use `kubectl scale`, delete workloads, or other bypasses to make shutdown appear complete. `kubectl drain` is an optional, one-worker-at-a-time evacuation branch for rolling maintenance while the cluster remains operating; use it only after application writers/jobs have stopped, the approved database shutdown procedure has completed, and the live K3s procedure allows it while the API and quorum remain healthy. Before each drain, check PDBs, DaemonSet pods, and storage detach/unmount requirements. Use the command shown below with an explicit context and worker name. If eviction is blocked or any check is unclear, stop this drain branch; resolve it under a workload-owner-approved procedure, or skip drain only for a full-cluster outage after its stated gates pass. Do not use `--force`, `--delete-emptydir-data`, or `--disable-eviction`. Never drain multiple nodes as a mass shortcut or drain a server node. Do not change Flux desired state or reconciliation state just to silence workloads.
- Do not treat automatic VM startup as confirmed. `docs/runbooks/iac-nixos-configurations.md` says VMs are left powered off, but `terraform/main.tf` sets both `on_boot = true` and `started = true` (and ignores changes to `started`). Confirm actual PVE settings and the intended behavior for every VM before shutdown and restart. Do not run OpenTofu to resolve this discrepancy.
- Treat every PVE, storage, database, and UPS action as an operator action that needs the live-approved procedure for that system.

## Repository facts and live-confirmation gates

These facts are confirmed in the repository; they do not prove the live state:

- The IaC VM inventory is in [`terraform/terraform.tfvars`](../../terraform/terraform.tfvars). Its current entries reference PVE nodes `pve01` through `pve04`; use that only as a comparison list, not as proof of the live PVE inventory. It is not a complete PVE/physical-device inventory.
- K3s server hosts use the HAProxy virtual IP as their server address, and HAProxy has K3s control-plane backends. See [`nixos/modules/k3s.nix`](../../nixos/modules/k3s.nix) and [`nixos/modules/haproxy.nix`](../../nixos/modules/haproxy.nix). HAProxy must therefore be available before K3s servers start relying on that address.
- K3s workloads use Synology CSI/iSCSI and NFS storage. The repository points these to `nas1.home.lab`; see [`nixos/modules/k3s.nix`](../../nixos/modules/k3s.nix) and [`kubernetes/infra/synology-csi/base/storageclass/`](../../kubernetes/infra/synology-csi/base/storageclass/). Confirm that the NAS and its exports/volumes are available before K3s workloads depend on them. The repository does **not** establish whether the NAS also provides PVE storage.
- Repository recovery/configuration indicates an etcd-backed K3s server cluster, and the existing IaC runbook treats etcd membership and quorum as important during recovery. See [`docs/runbooks/iac-terraform-opentofu-provisioning.md`](iac-terraform-opentofu-provisioning.md). Confirm the actual live datastore and membership, quorum, and approved whole-cluster shutdown and startup procedures before acting. Do not assume the live datastore, member count, or node order from this runbook.
- Flux manages infrastructure, monitoring, and application resources. The production Kustomization definitions are in [`fluxcd/clusters/production/infra.yaml`](../../fluxcd/clusters/production/infra.yaml), [`monitoring.yaml`](../../fluxcd/clusters/production/monitoring.yaml), and [`apps.yaml`](../../fluxcd/clusters/production/apps.yaml). The cluster recovery runbook documents database recovery boundaries: [`docs/runbooks/cluster-recovery.md`](cluster-recovery.md). Confirm live Flux Kustomization and HelmRelease readiness and suspension state before acting. Do not suspend, resume, or force reconciliation as part of this runbook without a separate approved plan.
- CNPG (CloudNativePG) manages PostgreSQL clusters. The repository includes a CNPG 1.27.0 manifest at [`kubernetes/infra/cloudnativepg/cnpg-1.27.0.yaml`](../../kubernetes/infra/cloudnativepg/cnpg-1.27.0.yaml), but the live operator version and supported shutdown method must be confirmed. **STOP:** do not proceed with database or K3s shutdown until both are confirmed from the installed operator and its matching procedure. This repository has no generic CNPG shutdown command. Do not guess at database commands or remove/scale resources.

Before proceeding, also confirm from the live PVE interface and approved operational records:

- Which PVE nodes, guests, physical hosts, network devices, storage systems, and UPS-backed devices are in scope, including guests absent from IaC.
- Current PVE cluster status, storage configuration/health, quorum, HA-managed guests, and whether Ceph is present. Confirm the approved PVE shutdown and startup procedure for those exact roles. **Do not proceed on an unknown or unhealthy state.**
- Whether the NAS is independent hardware, a VM, or a PVE storage dependency; identify the required NAS shutdown/startup method. If this creates a dependency cycle or its role is unclear, **STOP**.
- Current VM `on_boot` and startup-order behavior in PVE, including any differences from `terraform/main.tf`; identify which services are expected to start automatically and which require an operator action.
- Current K3s server/member health and etcd quorum, storage/PVC health, Flux Kustomization and HelmRelease state, and the installed CNPG operator version.
- Out-of-band access and the site-specific UPS/network-power sequence. This repository contains no approved UPS sequence; follow the equipment manufacturer and local electrical/safety procedures.

## Preflight inventory (read-only)

Record the output and the operator-confirmed live inventory before shutdown. These commands inspect state; they do not shut down or change resources. Set `CTX` to the exact context confirmed for this maintenance window. Each command names the context or live PVE target explicitly; do not copy a placeholder as a real host or context.

From the Kubernetes management host:

```sh
CTX='<verified-kubeconfig-context>'
kubectl config get-contexts "$CTX"
kubectl --context "$CTX" get nodes -o wide
kubectl --context "$CTX" get pods --all-namespaces -o wide
kubectl --context "$CTX" get pvc --all-namespaces
kubectl --context "$CTX" get pdb --all-namespaces
kubectl --context "$CTX" get clusters.postgresql.cnpg.io --all-namespaces
kubectl --context "$CTX" get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{range .items[*]}{.metadata.name}{" phase="}{.status.phase}{" "}{range .status.containerStatuses[*]}{.name}{" ready="}{.ready}{" image="}{.image}{" imageID="}{.imageID}{"\n"}{end}{end}'
flux get kustomizations --all-namespaces --context "$CTX"
flux get helmreleases --all-namespaces --context "$CTX"
```

The repository manifest identifies the controller pod in `cnpg-system` with label `app.kubernetes.io/name=cloudnative-pg`; the command prints pod phase and container status, including the image and image ID. Use the image from a Running, ready controller pod as an identification clue only. Confirm the actual installed operator version and its matching supported procedure before acting. If no matching pod appears or the live installation differs, discover the actual namespace/controller name first, then query that controller pod's container status image; do not infer a version from this repository's manifest.

From an approved management shell, connect to a **verified live PVE node**. Run cluster checks only where that node is healthy and the command applies; use the PVE configuration and operator records to confirm whether HA or Ceph is configured:

```sh
PVE_NODE='<verified-live-pve-node>'
ssh "root@$PVE_NODE" 'pvesh get /cluster/status'
ssh "root@$PVE_NODE" 'pvesh get /cluster/resources --type vm'
ssh "root@$PVE_NODE" 'pvecm status'
ssh "root@$PVE_NODE" 'pvesm status'
ssh "root@$PVE_NODE" 'ha-manager status'  # only if HA is configured
ssh "root@$PVE_NODE" 'ceph -s'            # only if Ceph is configured
```

Do not interpret a failed or missing command as proof that a feature is absent. Check the PVE configuration and operational records. Do not continue if cluster quorum, storage health, HA state, Ceph state, NAS role, VM state, or inventory cannot be established.

### Committed VM reference (stale-prone; not live inventory)

The following names, VM IDs, and PVE-node placements are copied from [`terraform/terraform.tfvars`](../../terraform/terraform.tfvars); corresponding NixOS host definitions are under [`nixos/hosts/`](../../nixos/hosts/). This is a repo-derived comparison list only. It can be stale or incomplete. Verify every VM ID and its current owning node against live PVE before use; it does not list all guests or physical hosts.

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

**Preflight go/no-go:** proceed only when the live inventory is complete for the requested scope, every dependency has a verified procedure, backups meet the operator's requirements, and all health/quorum/storage/HA gates above pass. If any item is unknown, unhealthy, or inconsistent with the expected state, **STOP**.

## Planned shutdown

Keep a log of each phase, target, result, and time. If the sequence is interrupted, repeat the read-only checks and continue from verified live state; do not repeat a power action blindly. Do not skip a phase because a service appears idle. The sequence below preserves dependencies where the repository establishes them; live PVE, NAS, and cluster rules take precedence.

1. **Quiesce and stop applications.** Notify users, stop external jobs and write-producing clients, then gracefully stop application workloads through each application's approved procedure. Confirm that active Flux reconciliation will not undo that procedure. Do not use generic scale/delete operations or suspend Flux as a shortcut; any needed Flux change requires a separate approved plan. Confirm backups and any required final data checks. If no approved application stop procedure exists, **STOP** before touching its database.
2. **Shut down databases by their supported procedure.** Confirm the running CNPG operator version and follow its matching shutdown guidance. Verify the expected database/cluster state after the procedure. Do not issue a guessed `kubectl`, SQL, container, or systemd shutdown command. If the installed version's procedure is unavailable or the result is unclear, **STOP**.
3. **Stop Kubernetes workloads and cluster through the approved process.** First pass the CNPG version-and-method STOP gate above. Confirm Flux state and follow the live K3s shutdown procedure for the confirmed datastore and member topology. Preserve quorum until that procedure says the cluster can be stopped; follow its exact member/quorum ordering, and do not invent an order or power off a subset of server members based on this document.

   **Full-cluster outage:** `kubectl drain` is optional; it evacuates a node while the cluster remains operating, and PDBs govern eviction API requests such as drain, not guest poweroff. Direct VM shutdown does not guarantee graceful application/database shutdown. The repository's NixOS [K3s configuration](../../nixos/modules/k3s.nix) does not explicitly set kubelet graceful-node-shutdown grace periods, so do not assume `systemctl poweroff` gives pods enough time. After writers/jobs and stateful databases are safely quiesced using owner/version-specific procedures and the CNPG STOP gate above passes, the approved whole-cluster K3s/etcd procedure may allow graceful per-guest shutdown without draining every worker; follow its exact member/quorum order and proceed only if that procedure allows it.

   **Optional drain branch — rolling maintenance while the cluster remains operating:** drain one worker only after app writers/jobs have stopped, the installed-version-specific database shutdown procedure has completed, storage checks are clear, and the live K3s procedure permits evacuation while API and quorum remain healthy. Check PDBs and DaemonSet pods and confirm each affected volume can detach/unmount. Set the explicit context and worker name, then drain **one verified worker only**. Confirm `$NODE` names a worker, not a server, before running the command:

   ```sh
   CTX='<verified-kubeconfig-context>'
   NODE='<verified-worker-node-name>'
   kubectl --context "$CTX" get pdb --all-namespaces
   kubectl --context "$CTX" get daemonsets --all-namespaces
   kubectl --context "$CTX" get pods --all-namespaces -o wide --field-selector "spec.nodeName=$NODE"
   kubectl --context "$CTX" get pvc --all-namespaces
   kubectl --context "$CTX" get pv
   ```

   **STOP / REVIEW:** inspect all check output. Confirm `$NODE` is the exact live worker to drain, API and quorum are healthy, each affected volume can detach, and the approved K3s procedure authorizes this action. Run only the separate drain command below; never paste or run the check and action blocks as a batch.

   ```sh
   kubectl --context "$CTX" drain "$NODE" --ignore-daemonsets --timeout=10m
   ```

   **STOP:** if drain is blocked or times out, stop this drain branch; do not force it or try another worker. Resolve the block under a workload-owner-approved procedure, or skip drain only for a full-cluster outage after the full-outage gates above pass. After a successful drain, inspect its status separately:

   ```sh
   kubectl --context "$CTX" get node "$NODE" -o wide
   ```

   Do not use `--force`, `--delete-emptydir-data`, or `--disable-eviction`; do not drain a server or another worker as a shortcut. After a successful rolling-maintenance drain, follow the approved live K3s member procedure. Shut down a NixOS guest only when that procedure and all database, workload, storage, and quorum gates permit that specific guest. The SSH poweroff command in phase 4 is for an individually verified guest and is not a K3s member-order procedure.

4. **Shut down guests one at a time, excluding the NAS VM and other storage dependencies.** Keep DNS and HAProxy available until they are no longer needed for user access, name resolution, or management. For each in-scope guest, verify its live identity and check its relevant services first. For a K3s guest, do not proceed until the approved member procedure permits shutting down that member. All Kubernetes preconditions above must pass: app writers/jobs are stopped, CNPG's installed version and supported shutdown method are confirmed and completed, any selected rolling-maintenance drain is complete, and the live procedure confirms the required member/quorum ordering and safety for this shutdown. A drain is not a prerequisite for the full-cluster outage path. Set these values for the exact live guest, then inspect the output; these commands only check state:

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

5. **Resolve the NAS/PVE shutdown dependency.** Phase 4 excludes the NAS VM and all other storage dependencies; this phase owns their shutdown. Keep NAS/storage online until all dependents are stopped. If the NAS is a PVE guest, gracefully stop it only after its dependents stop and the approved storage/PVE shutdown order for its exact role and host is confirmed. If the NAS provides PVE storage, follow that approved storage-specific procedure; do not infer whether NAS or PVE stops first. If the role, dependent state, or approved order is unknown, **STOP**.
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
6. **Verify nodes, storage, Flux, and guests before applications.** Set `CTX` to the verified cluster context. After the live K3s procedure says the API is available, wait for nodes to become Ready and inspect nodes, workloads, volumes, and CNPG. Then inspect Flux status. These are read-only checks:

   ```sh
   CTX='<verified-kubeconfig-context>'
   kubectl --context "$CTX" wait --for=condition=Ready nodes --all --timeout=10m
   kubectl --context "$CTX" get nodes -o wide
   kubectl --context "$CTX" get pods --all-namespaces -o wide
   kubectl --context "$CTX" get pvc --all-namespaces
   kubectl --context "$CTX" get clusters.postgresql.cnpg.io --all-namespaces
   kubectl --context "$CTX" get pods -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{range .items[*]}{.metadata.name}{" phase="}{.status.phase}{" "}{range .status.containerStatuses[*]}{.name}{" ready="}{.ready}{" image="}{.image}{" imageID="}{.imageID}{"\n"}{end}{end}'
   flux get kustomizations --all-namespaces --context "$CTX"
   flux get helmreleases --all-namespaces --context "$CTX"
   ```

   If a worker was drained for this shutdown, uncordon only after that specific node is back and Ready and the approved cluster procedure permits workloads to return to it:

   ```sh
   NODE='<verified-worker-node-name>'
   kubectl --context "$CTX" wait --for=condition=Ready "node/$NODE" --timeout=10m
   kubectl --context "$CTX" get node "$NODE" -o wide
   ```

   **STOP / REVIEW:** inspect the output and confirm this is the exact worker drained for this shutdown, it is Ready, and the approved cluster procedure permits it to receive workloads. Run only the separate action below; never paste or run the checks and action as a batch.

   ```sh
   kubectl --context "$CTX" uncordon "$NODE"
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

Stop the sequence and do not improvise if:

- Live PVE topology, quorum, storage, HA, Ceph, VM auto-start, or guest inventory is unknown or differs from the planned inventory.
- NAS role or storage dependencies are unknown, or the NAS/PVE shutdown or startup order cannot be determined safely.
- Out-of-band access, credentials, or the approved UPS/electrical procedure is unavailable.
- K3s etcd member state/quorum is unhealthy or unknown, or a server would be stopped/started outside the approved cluster procedure.
- Flux Kustomization/HelmRelease status or suspension state is unexpected.
- CNPG version-specific shutdown guidance is missing, or database status is uncertain.
- A guest does not shut down cleanly, a storage check fails, or a startup health gate does not pass.

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
- [ ] K3s stopped through the approved whole-cluster member/quorum-order procedure; drain is optional for a full-cluster outage and may be skipped only after writers/jobs and stateful databases are safely quiesced under owner/version-specific procedures and the approved procedure allows graceful per-guest shutdown. For rolling maintenance, drain one worker only after writers/jobs and database procedures complete, with API/quorum healthy and PDB/DaemonSet/storage checks passed; stop that branch if blocked and resolve it under a workload-owner-approved procedure. Never use force, local-data deletion, eviction bypass, server-node drain, or mass drain.
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
