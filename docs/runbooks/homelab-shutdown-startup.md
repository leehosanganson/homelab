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

Follow the approved database procedure before taking K3s down, including pausing writes if required. A graceful VM shutdown alone does not guarantee a clean database shutdown. **STOP** if the database procedure or safe state is unclear. There is no generic database shutdown command documented here. Do not bypass database safeguards or delete persistent volume claims (PVCs).

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

Before switching off network equipment or the UPS, confirm that every device that will lose power has been safely shut down and that every device that will stay powered but lose connectivity (such as a NAS on a separate power supply) can safely operate without network access or has been intentionally taken offline. Follow the approved site procedure and do not assume an unreachable device is off.

## Startup

### 1. Restore the network, storage, and PVE

Restore power and the management network using the approved site procedure. Use direct management addresses if DNS is not up yet. Bring up any independent backing storage that PVE hosts need before starting those hosts.

Start PVE using the approved cluster procedure. In the PVE UI, confirm quorum, backing storage health, and Ceph and HA health where configured. **STOP** if PVE or required backing storage is unhealthy.

If the NAS runs as a guest, its exports are not available at PVE startup. Start the NAS guest only once its PVE host and its own backing storage are ready, then verify the NAS exports before starting any guest that depends on them.

### 2. Start DNS, HAProxy, and K3s

Check what PVE has already started automatically. Start DNS and HAProxy through the PVE UI as needed, and confirm the HAProxy virtual IP is available before bringing up K3s servers that rely on it.

Confirm K3s workload storage is available, then start K3s servers as needed in the approved etcd member order. Verify quorum and Kubernetes API health before starting any remaining workers. Start other guests from the PVE UI as needed once their dependencies are ready.

### 3. Let Flux reconcile and verify

Once K3s is back, Flux reconciles the desired state from Git. Let it run normally instead of bringing individual services back by hand.

```sh
kubectl get nodes
kubectl get pods -A
kubectl get clusters.postgresql.cnpg.io -A
flux get kustomizations -A
flux get helmreleases -A
```

Confirm the expected nodes, pods, and Flux resources are healthy. Use the procedure for the installed CloudNativePG (CNPG) version to confirm the expected PostgreSQL clusters are healthy. Check that DNS and critical applications work from their usual access paths and that data is available. Resume any paused application writes only after the databases and affected applications are healthy.

Before declaring startup successful, verify that the intended PVE auto-start and HA settings are restored, including any settings temporarily changed for the outage.

If a data restore is needed, use the [cluster recovery runbook](cluster-recovery.md).
