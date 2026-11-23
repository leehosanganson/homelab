# Whole-Homelab Shutdown and Startup

Use this runbook for a planned full outage, not rolling maintenance. Use the live Proxmox VE (PVE) UI to find guests and their current hosts. You do not need to maintain a separate VM inventory.

## Before shutdown

- Verify access to the K3s cluster and the PVE UI. Test console or out-of-band access that does not depend on homelab DNS or HAProxy, so you can still reach the hosts after those services stop.
- Verify that required backups are current and successful, and that K3s, PVE, and required storage are healthy. **STOP** if a backup failed or cluster or storage health is not as expected.
- **STOP** if the K3s datastore, etcd members or quorum, or the approved K3s shutdown and startup order is unclear. Do not guess which members to stop or start.
- **STOP** if the PVE cluster shutdown or startup procedure is unclear, including any Ceph, shared storage, or high availability (HA) requirements. This runbook does not specify a PVE host or Ceph shutdown order.
- **STOP** before physical host or uninterruptible power supply (UPS) actions if the approved site power procedure is unclear.

## Shutdown

### 1. Prepare K3s for the outage

For a full outage, you do not need to scale or suspend GitOps-managed services. Pod Disruption Budgets (PDBs) can block `kubectl drain`, but a full-cluster shutdown does not require draining, so PDBs do not block this shutdown procedure. Do not bypass PDBs.

Follow the approved database procedure before taking K3s down, including pausing writes if required. A graceful VM shutdown alone does not guarantee a clean database shutdown. **STOP** if the database procedure or safe state is unclear. Do not bypass database safeguards or delete persistent volume claims (PVCs).

For CloudNativePG (CNPG), complete the checks below before pausing writes. Confirm the intended Kubernetes context and review the full live cluster list by namespace and name:

```sh
kubectl config current-context
kubectl get clusters.postgresql.cnpg.io -A
```

**STOP** if you cannot verify the context or inventory, the inventory is empty, any expected cluster is missing, or any listed cluster is not approved for both hibernation and reactivation. Record the verified and approved namespace/name list and its count for this outage before pausing writes. Use that record for both shutdown and startup checks. The [CNPG helper](../../scripts/cnpg-hibernate.sh) operates across all namespaces, and `off` wakes every hibernated cluster, including any hibernated before the outage.

Before pausing writes, run `./scripts/cnpg-hibernate.sh --help` from the repo root and verify the prerequisites separately: Bash 5+, GNU `timeout`, `jq`, `kubectl`, and the `kubectl cnpg` plugin. Run these read-only checks in the verified context:

```sh
kubectl cnpg version
kubectl cnpg hibernate on --help
kubectl cnpg hibernate off --help
kubectl -n cnpg-system get deployment cnpg-controller-manager -o yaml
```

Confirm both help commands succeed and advertise their respective usage: `kubectl cnpg hibernate on CLUSTER` and `kubectl cnpg hibernate off CLUSTER`. The plugin must report a stable `1.27.N` release (not a prerelease). The operator's `manager` container image must use the `/cloudnative-pg:1.27.N` image/tag form (an optional `@sha256:` digest is allowed). The plugin patch number must be at least the operator patch number.

In the Deployment YAML, confirm `.status.observedGeneration == .metadata.generation` and `.spec.replicas > 0`. The helper requires `.status.updatedReplicas`, `.status.replicas`, and `.status.availableReplicas` each to equal `.spec.replicas`; also verify `.status.readyReplicas` equals `.spec.replicas`. Confirm the `manager` container has no `envFrom` sources and `WATCH_NAMESPACE` is absent or empty, with no `valueFrom`.

If `CNPG_HIBERNATE_TIMEOUT_SECONDS` is nonempty, it must be a positive integer of 1 to 6 digits with no leading zero. An unset or empty value uses the 300-second default. **STOP** before pausing writes if any prerequisite is unmet or unverified.

Pause application writes to the CNPG databases before hibernating them. The pause must remain effective through guest restart and Flux reconciliation. **STOP** if you cannot ensure it will stay in effect until all recovery gates pass. From a terminal at the repo root, run:

```sh
./scripts/cnpg-hibernate.sh on
```

The helper checks the context, operator, and plugin, then lists all targets by namespace and name. Type `yes` only if the displayed context is the verified context and the confirmation list matches the recorded namespace/name targets exactly. Wait for it to verify that every target is hibernated, its instance pods are gone, and the same PVCs remain bound. Before taking K3s down, require a zero exit and a `Hibernate on` summary with the recorded target count verified and `0 failed`. `No CNPG Clusters found.` is not success, even with a zero exit. If that message appears or the summary is missing or mismatched, recheck the target list and count against the outage record.

**STOP** if `on` fails any of these checks, does not finish, or leaves any target's state unclear. The helper may issue `off` to cancel an unverified new `on` attempt, so that cluster may be awake while successful targets remain hibernated. An in-flight `on` may still take effect. Manually reconcile the affected clusters before retrying or taking K3s down.

Follow the approved K3s/etcd shutdown order when taking down the K3s guests.

### 2. Shut down guests gracefully

Keep DNS, HAProxy, and storage online until their dependents no longer need them. Where HA manages a guest, use the approved HA procedure to take it offline without triggering a restart or move.

Use the PVE UI or run `qm list` on the relevant PVE host to find the VM ID and confirm the target:

```sh
qm list
```

On the VM's current PVE host, replace the placeholder with the verified numeric ID, then request a graceful shutdown:

```sh
VMID='<verified-vm-id>'
qm shutdown "$VMID" --timeout 300
```

Check the result separately before moving on:

```sh
qm status "$VMID"
```

Confirm the VM reports `stopped`. **STOP** if the shutdown times out or the VM does not stop cleanly. Do not use a force-stop or cut power to a running guest.

### 3. Shut down PVE, then network and power if in scope

Before shutting down any PVE host, use the approved PVE procedure to verify live guest auto-start and HA settings and adjust them now as needed to enforce the storage, DNS, HAProxy, and K3s startup sequence. **STOP** if you cannot confirm that dependency-sensitive guests will wait for their prerequisites.

Once the guests are down, shut down the PVE hosts using the approved procedure for this cluster's quorum, HA, and storage. Keep any NAS or other storage online until its dependents are down and the storage procedure allows it to stop.

If the Synology NAS is in scope, keep it on until dependent guests are down and any remaining storage clients no longer need it. Confirm in DSM that no transfers or storage tasks are active, then shut it down from the DSM UI and confirm it is off.

Before switching off network equipment or the UPS, confirm that devices losing power are safely shut down and that devices staying powered can safely lose connectivity. **STOP** if the site procedure is unclear. Only if network equipment is in the outage scope, shut down the Ubiquiti router and switches in the approved site-specific order. Then follow the approved UPS procedure if in scope. Do not assume an unreachable device is off.

## Startup

### 1. Restore the network, storage, and PVE

**STOP** if the site procedure is unclear. Restore power using the approved site procedure. Then power up only the router and switches that were shut down as part of the outage, following the approved site-specific order. Verify management and storage network connectivity before starting storage or hosts. Use direct management addresses if DNS is not up yet.

You can start the standalone Synology NAS and check storage health in DSM before starting PVE. Bring up any independent backing storage that PVE hosts need before starting those hosts.

Start PVE using the approved cluster procedure. In the PVE UI, confirm quorum, backing storage health, and Ceph and HA health where configured. **STOP** if PVE or required backing storage is unhealthy.

If the NAS runs as a guest, its exports are not available at PVE startup. Start the NAS guest only once its PVE host and its own backing storage are ready.

After the PVE hosts and NAS are running, verify from the consuming hosts that the required NFS exports or iSCSI targets and LUNs are available before starting dependent guests. **STOP** if required storage is unavailable.

### 2. Start DNS, HAProxy, and K3s

Check what PVE has already started automatically. Start DNS and HAProxy through the PVE UI as needed, and confirm the HAProxy virtual IP is available before bringing up K3s servers that rely on it.

Confirm K3s workload storage is available, then start K3s servers as needed in the approved etcd member order. Verify quorum and Kubernetes API health before starting any remaining workers. Start other guests from the PVE UI as needed once their dependencies are ready.

### 3. Let Flux reconcile and verify

Once K3s is back, Flux reconciles the desired state from Git. Let it run normally instead of bringing individual services back by hand.

Once the CNPG operator and database storage are ready, recheck the Kubernetes context and compare the full live namespace/name list and count against the approved list and count recorded at shutdown. **STOP** and keep writes paused if you cannot verify the context or inventory, the inventory is empty, any expected cluster is missing, or any listed cluster is not on the recorded list or must stay hibernated. `off` wakes all hibernated clusters, not just those hibernated during shutdown.

Repeat the read-only plugin and operator checks from shutdown. Verify both hibernate help outputs, the stable `1.27.N` plugin release, and the operator's `manager` image/tag as in shutdown. Confirm the plugin patch is at least the operator patch. Verify operator readiness: the observed generation matches, the desired replica count is positive, and the total, updated, available, and ready replica counts all match it. Verify the operator watches all namespaces: the `manager` container has no `envFrom`, and `WATCH_NAMESPACE` is absent or empty with no `valueFrom`.

Verify that the application write pause is still effective before running `off`. **STOP** without running `off` if the pause or any repeated check fails or cannot be verified.

From a terminal at the repo root, run:

```sh
./scripts/cnpg-hibernate.sh off
```

Type `yes` only if the displayed context is the verified context and the helper's confirmation list matches the recorded namespace/name targets exactly. Wait for the helper to verify that every cluster is healthy and all expected instances are ready. Before resuming writes, require a zero exit and a `Hibernate off` summary with the recorded target count verified and `0 failed`. `No CNPG Clusters found.` is not success, even with a zero exit. If that message appears or the summary is missing or mismatched, recheck the target list and count against the outage record. **STOP** and keep writes paused if any check fails or recovery is not verified.

```sh
kubectl get nodes
kubectl get pods -A
kubectl get clusters.postgresql.cnpg.io -A
flux get kustomizations -A
flux get helmreleases -A
```

Confirm the expected nodes, pods, PostgreSQL clusters, and Flux resources are healthy. Check that DNS and critical applications work from their usual access paths and that data is available.

Before declaring startup successful, verify that the intended PVE auto-start and HA settings are restored, including any settings temporarily changed for the outage.

If a data restore is needed, use the [cluster recovery runbook](cluster-recovery.md).

Resume application writes only after all recovery checks pass.
