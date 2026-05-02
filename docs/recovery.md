# Cluster Recovery Playbook

This document is the step-by-step playbook for recovering the Kubernetes cluster from scratch. It covers bootstrapping Flux, restoring stateful workloads via Velero, recovering CNPG databases from barman backups, and allowing Flux to reconcile the rest.

## Overview

Recovery must follow a strict order because later phases depend on resources created in earlier ones.

```
Phase 1: Bootstrap Flux
     ↓
Phase 2: Reconcile Infrastructure (External Secrets → Storage → Velero → CNPG)
     ↓
Phase 3: Velero Restore (stateful app namespaces)
     ↓
Phase 4: CNPG Database Recovery (automatic via recovery bootstrap)
     ↓
Phase 5: Reconcile Monitoring
     ↓
Phase 6: Reconcile Applications (stateless services)
```

---

## Prerequisites

- `kubectl` configured against the new cluster
- Azure CLI (`az`) authenticated with access to `lhs-kubernetes-keyvault`
- `flux` CLI installed
- `velero` CLI installed
- The Azure Service Principal credentials for External Secrets Operator (ClientID, ClientSecret)

---

## Phase 1: Bootstrap Flux

Flux is the foundation — it manages all other resources. Bootstrap it first using the script at `fluxcd/bootstrap.sh`.

```bash
# This script reads the GitHub token from Azure Key Vault and runs flux bootstrap
./fluxcd/bootstrap.sh
```

This creates the `flux-system` namespace and installs Flux components. It will then try to reconcile `infra`, `monitoring`, and `apps` kustomizations — most will fail initially because External Secrets is not yet working. That is expected.

---

## Phase 2: Reconcile Infrastructure

### Step 1: Seed the External Secrets Service Principal

External Secrets Operator (ESO) authenticates to Azure Key Vault via a Service Principal. This secret is not managed by ESO itself (that would be circular), so it must be created manually before ESO can pull any other secrets.

```bash
kubectl create namespace external-secrets

kubectl create secret generic azure-sp-secret \
  --namespace=external-secrets \
  --from-literal=ClientID=<sp-client-id> \
  --from-literal=ClientSecret=<sp-client-secret>
```

> The Service Principal credentials can be found in Azure Key Vault under the secret name referenced in
> `kubernetes/infra/external-secrets/overlays/default/azure-kv-secret.yaml.example`.

### Step 2: Wait for Infrastructure to Reconcile

Once the ESO secret is in place, trigger a reconciliation and wait:

```bash
flux reconcile kustomization infra-production --with-source
flux get kustomizations --watch
```

Flux will install and configure (in order, as defined in `kubernetes/infra/overlays/production/kustomization.yaml`):

| Component | Purpose |
|-----------|---------|
| Cert Manager | TLS certificates |
| External Secrets Operator | Pulls secrets from Azure Key Vault |
| Traefik | Ingress controller |
| Synology CSI | Storage class provisioner |
| CloudNativePG | PostgreSQL cluster operator |
| Velero | Backup / restore agent |
| Rancher | Cluster management UI |
| Harbor | Container registry |
| Renovate | Dependency updates |

### Step 3: Verify Velero Is Ready

```bash
kubectl get pods -n velero
velero get backup-locations
```

The `default` backup storage location should show `Available`. If it shows `Unavailable`, check that ESO has synced the `cloud-credentials` secret in the `velero` namespace.

---

## Phase 3: Velero Restore

The Velero schedule (`kubernetes/infra/velero/overlays/default/backup-schedule.yaml`) runs daily at 07:00 UTC and backs up the following namespaces:

| Namespace | App | Contents |
|-----------|-----|----------|
| `actual-budget` | Actual Budget | Deployment, PVC |
| `grimmory` | Grimmory | Deployment, MariaDB PVC, data PVCs |
| `home-assistant` | Home Assistant | Deployment, PVC |
| `immich` | Immich | Deployment, NFS photo library PV/PVC |
| `karakeep` | Karakeep | Deployment, PVCs |
| `llm` | Open WebUI | Deployment, PVC |
| `media` | Media stack (*arr) | Deployments, PVCs |
| `minecraft` | Minecraft | Deployment, 50Gi game data PVC |
| `n8n` | n8n | Deployment, PVC (database backed up separately via CNPG) |
| `navidrome` | Navidrome | Deployment, config PVC, NFS music PV/PVC |
| `paperless` | Paperless-ngx | Deployment, PVCs (database backed up separately via CNPG) |
| `syncthing` | Syncthing | Deployment, config PVC, NFS data PV/PVC |
| `zotero` | Zotero WebDAV | Deployment, PVC |

The backup includes the Kubernetes object manifests for `deployments`, `pods`, `persistentvolumes`, `persistentvolumeclaims`, and `namespaces`.

### List Available Backups

```bash
velero get backups
```

Backups are retained for 10 days (240h TTL). Pick the most recent backup from the list.

### Restore All Covered Namespaces

```bash
velero restore create --from-backup <backup-name>
```

### Restore a Single Namespace

```bash
velero restore create \
  --from-backup <backup-name> \
  --include-namespaces actual-budget
```

### Monitor Restore Progress

```bash
velero restore get
velero restore describe <restore-name> --details
```

Wait until all restores show `Completed` before moving to Phase 4. PVCs must be in `Bound` state before the dependent applications can start.

---

## Phase 4: CNPG Database Recovery

CNPG clusters continuously archive WAL to Azure Blob Storage via the barman-cloud plugin. Each cluster has a corresponding `ObjectStore` resource and a scheduled base backup. All cluster manifests use `bootstrap.recovery` so that Flux automatically recovers each database from the latest barman backup when the cluster is first created on the new cluster.

### Cluster Inventory

| Cluster | Namespace | Barman Object Store | Azure Blob Path |
|---------|-----------|--------------------|--------------------|
| `immich-db` | `immich` | `immich-backup-storage` | `lhshomelabbackup/immich` |
| `n8n-db` | `n8n` | `n8n-backup-storage` | `lhshomelabbackup/n8n` |
| `paperless-db` | `paperless` | `paperless-backup-storage` | `lhshomelabbackup/paperless` |
| `commafeed-db` | `commafeed` | `commafeed-backup-storage` | `lhshomelabbackup/commafeed` |
| `litellm-db` | `litellm` | `litellm-backup-storage` | `lhshomelabbackup/litellm` |
| `coder-db` | `coder` | `coder-backup-storage` | `lhshomelabbackup/coder` |
| `life-in-the-uk-quiz-db` | `life-in-the-uk-quiz` | `life-in-the-uk-quiz-backup-storage` | `lhshomelabbackup/life-in-the-uk-quiz` |

### Recovery Procedure (per cluster)

When Flux reconciles the `apps-production` kustomization, each CNPG cluster is created with `bootstrap.recovery.source: clusterBackup`. CNPG will automatically recover from the latest barman backup in the configured `ObjectStore`.

**Prerequisites before Flux creates the cluster:**

1. **The `ObjectStore` resource and its secret must exist** in the namespace (Flux deploys these as part of the app kustomization before creating the Cluster). Verify:

   ```bash
   kubectl get objectstore -n <namespace>
   kubectl get secret -n <namespace> | grep backup
   ```

2. **Watch recovery progress** once the cluster is created:

   ```bash
   kubectl get cluster <cluster-name> -n <namespace> -w
   kubectl describe cluster <cluster-name> -n <namespace>
   ```

   The cluster will enter a `Recovering` phase while it restores the base backup and replays WAL segments. Once the cluster shows `Cluster in healthy state`, the database is ready.

**If the cluster was accidentally created before backups were available (e.g. during a new cluster bootstrap with no existing backups):**

```bash
# Delete the cluster and its PVCs to force a recreate
kubectl delete cluster <cluster-name> -n <namespace>
kubectl delete pvc -l cnpg.io/cluster=<cluster-name> -n <namespace>

# Flux will recreate the cluster on next reconcile
flux reconcile kustomization apps-production
```

> **Note for fresh cluster with no prior backups:** `bootstrap.recovery` will fail if no barman backup
> exists. In that case, temporarily patch the cluster manifest to use `bootstrap.initdb`, apply it,
> let the cluster initialise, then revert the manifest once WAL archiving has produced a base backup.

### Verify Data After Recovery

For each cluster, connect to the primary pod and verify the database:

```bash
kubectl exec -it <cluster-name>-1 -n <namespace> -- psql -U postgres
```

```sql
\l         -- list databases
\dt        -- list tables in current db
SELECT COUNT(*) FROM <key_table>;
```

---

## Phase 5: Reconcile Monitoring

Once infrastructure is healthy, bring up the monitoring stack:

```bash
flux reconcile kustomization monitoring-production --with-source
flux get kustomizations monitoring-production --watch
```

This deploys Prometheus, Grafana, Loki, Alloy, and Uptime Kuma.

---

## Phase 6: Reconcile Applications

With infrastructure, databases, and monitoring in place, allow Flux to reconcile all remaining applications:

```bash
flux resume kustomization apps-production
flux reconcile kustomization apps-production --with-source
flux get kustomizations apps-production --watch
```

Applications in namespaces restored by Velero (Phase 3) will see their PVCs already bound. Applications backed by CNPG databases recovered in Phase 4 will connect to their restored databases. The remaining stateless services will be deployed fresh from the Git manifests.

---

## Verification Checklist

After all phases are complete, verify the cluster health:

```bash
# All pods running
kubectl get pods -A | grep -v Running | grep -v Completed

# All CNPG clusters healthy
kubectl get cluster -A

# All Flux kustomizations ready
flux get kustomizations

# Velero restore status
velero restore get

# Certificate health
kubectl get certificates -A

# Ingress routes
kubectl get ingressroute -A
```

---

## Troubleshooting

### External Secrets not syncing

Check that the `azure-sp-secret` exists in the `external-secrets` namespace and has the correct keys (`ClientID`, `ClientSecret`). Then force a sync:

```bash
kubectl annotate externalsecret -n <namespace> <name> \
  force-sync=$(date +%s) --overwrite
```

### CNPG cluster stuck in `Recovering`

Check the cluster events and the primary pod logs:

```bash
kubectl describe cluster <cluster-name> -n <namespace>
kubectl logs <cluster-name>-1 -n <namespace> -c postgres
```

Common causes:
- The `ObjectStore` secret (barman SAS token) has not been synced by ESO yet
- The barman backup does not contain a full base backup — check WAL archive completeness:
  ```bash
  kubectl exec -it <cluster-name>-1 -n <namespace> -- \
    barman-cloud-backup-list --format json \
    <azure-blob-path> <server-name>
  ```

### Velero restore fails for PVCs

Velero backs up PVC/PV objects but volume data is not included in file-system backups when `defaultVolumesToFsBackup: false` is set in the schedule. The Synology CSI driver handles volume provisioning; data on the NAS is preserved independently. If a PVC is restored but shows `Pending`, check that the `synology-retain` storage class is available and the Synology CSI driver is running:

```bash
kubectl get storageclass
kubectl get pods -n synology-csi
```
