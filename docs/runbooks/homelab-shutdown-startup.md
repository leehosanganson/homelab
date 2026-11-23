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

For CloudNativePG (CNPG), confirm the Kubernetes context, check the live operator image and readiness, and identify the clusters approved for hibernation:

```sh
kubectl config current-context
kubectl get deployments -A -l app.kubernetes.io/name=cloudnative-pg -o wide
kubectl get clusters.postgresql.cnpg.io -A
```

**STOP** if you cannot confirm the intended context, a healthy operator, its version, or the target clusters. Use the steps below only for [CNPG 1.27](https://cloudnative-pg.io/docs/1.27/declarative_hibernation/); for another version, use its approved procedure.

Run `kubectl cnpg version`. **STOP** if the plugin is unavailable or you cannot confirm it is compatible with the live operator (same version or newer).

Leave already hibernated clusters alone. Pause writes to each remaining target and record its namespace and name for startup. Replace the placeholders and run these commands for each target:

```sh
NS='<namespace>'
CLUSTER='<cluster-name>'
kubectl cnpg -n "$NS" hibernate on "$CLUSTER"
kubectl cnpg -n "$NS" status "$CLUSTER"
kubectl -n "$NS" get pods,pvc -l "cnpg.io/cluster=$CLUSTER"
```

Repeat the checks until `kubectl cnpg status` reports `Hibernated`, no instance pods remain, and the expected PVCs are still present. **STOP** if any target does not reach this state.

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

Once the CNPG operator and database storage are ready, rehydrate only the clusters hibernated for this outage. Recheck the context, live operator version, plugin compatibility, and recorded targets as in shutdown. For CNPG 1.27, set `NS` and `CLUSTER` to the verified values for each target, then run:

```sh
kubectl cnpg -n "$NS" hibernate off "$CLUSTER"
kubectl cnpg -n "$NS" status "$CLUSTER"
```

Repeat the status check until each rehydrated cluster reports `Cluster in healthy state` and all expected instances are ready. **STOP** if any target does not recover.

```sh
kubectl get nodes
kubectl get pods -A
kubectl get clusters.postgresql.cnpg.io -A
flux get kustomizations -A
flux get helmreleases -A
```

Confirm the expected nodes, pods, and Flux resources are healthy. Use the procedure for the installed CNPG version to confirm the expected PostgreSQL clusters are healthy. Check that DNS and critical applications work from their usual access paths and that data is available. Resume any paused application writes only after the databases and affected applications are healthy.

Before declaring startup successful, verify that the intended PVE auto-start and HA settings are restored, including any settings temporarily changed for the outage.

If a data restore is needed, use the [cluster recovery runbook](cluster-recovery.md).
