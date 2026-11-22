# Cluster Recovery

Procedures for recovering the Kubernetes cluster from scratch, covering bootstrapping Flux, restoring stateful workloads via Velero, recovering CNPG databases from barman backups, and allowing Flux to reconcile the rest.

## Overview

Recovery must follow a strict order because later phases depend on resources created in earlier ones.

```
Phase 1: Bootstrap Flux
     ↓
Phase 2: Reconcile Infrastructure (External Secrets → Storage → Velero → CNPG → Harbor)
     ↓
Phase 3: Velero Restore (apps + harbor namespaces)
     ↓
Phase 4: CNPG Database Recovery (requires an explicit replacement-cluster plan)
     ↓
Phase 5: Reconcile Monitoring
     ↓
Phase 6: Reconcile Applications (stateless services)
```

---

## Prerequisites

Ensure the following tools are available and configured before starting:

- `kubectl` configured against the new cluster
- Azure CLI (`az`) authenticated with access to `lhs-kubernetes-keyvault`
- `flux` CLI installed
- `velero` CLI installed
- The Azure Service Principal credentials for External Secrets Operator (ClientID, ClientSecret)
  - These are stored in Azure Key Vault; retrieve them with:

    ```bash
    az keyvault secret show --vault-name lhs-kubernetes-keyvault --name <sp-client-id-secret>
    az keyvault secret show --vault-name lhs-kubernetes-keyvault --name <sp-client-secret-secret>
    ```

---

## Phase 1 — Bootstrap Flux

Flux is the foundation — it manages all other resources. Bootstrap it first using the script at `fluxcd/bootstrap.sh`.

```bash
# Run from the repo root; the script reads the GitHub token from Azure Key Vault
./fluxcd/bootstrap.sh
```

This creates the `flux-system` namespace and installs Flux components. The production root reconciles the `infra-production`, `monitoring-production`, `apps-production`, and dedicated `authentik-production` Kustomization resources. The `authentik-production` child must remain suspended and must not apply its workload during recovery. Other Kustomizations may fail initially because External Secrets Operator (ESO) has not yet synced any secrets; that is expected.

**Verify Flux is running:**

```bash
kubectl get pods -n flux-system
flux get kustomizations
```

### 1.1 — Suspend app/monitoring reconciliation before recovery actions

Before running restores or database recovery, suspend `apps-production` and `monitoring-production` so Flux does not race ahead while PVCs and databases are being restored.

```bash
flux suspend kustomization apps-production
flux suspend kustomization monitoring-production
flux get kustomizations
```

`infra-production` should remain active. It excludes the Authentik workload and database. Before recovery actions, verify that the Git-managed `authentik-production` resource has `spec.suspend: true` and that the production root has reconciled it. If it is not suspended in Git, make a reviewed Git change and wait for the root to apply it; `flux suspend` alone is not durable because the root would restore the Git value. Keep this Kustomization suspended for the entire recovery; do not resume it or apply the Authentik overlay as a fresh `initdb` deployment. If Authentik data needs recovery, follow the Phase 4 stop boundary and require an explicit new-Cluster recovery plan.

---

## Phase 2 — Reconcile Infrastructure

### 2.1 — Seed the External Secrets Service Principal

ESO authenticates to Azure Key Vault via a Service Principal. This secret cannot be managed by ESO itself (that would be circular), so it must be seeded manually before ESO can pull any other secrets.

```bash
kubectl create namespace external-secrets

kubectl create secret generic azure-sp-secret \
  --namespace=external-secrets \
  --from-literal=ClientID=<sp-client-id> \
  --from-literal=ClientSecret=<sp-client-secret>
```

> The secret name and required keys are referenced in
> `kubernetes/infra/external-secrets/overlays/default/azure-kv-secret.yaml.example`.

### 2.2 — Reconcile Infrastructure

Trigger a reconcile and wait for all infra components to become ready:

```bash
flux reconcile kustomization infra-production --with-source
flux get kustomizations --watch
```

`infra-production` installs its components (as defined in `kubernetes/infra/overlays/production/kustomization.yaml`); it does not create Authentik or its database:

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| Cert Manager | `cert-manager` | TLS certificate issuance |
| External Secrets Operator | `external-secrets` | Pulls secrets from Azure Key Vault |
| Traefik | `traefik` | Ingress controller |
| Synology CSI | `synology-csi` | Storage class provisioner |
| CloudNativePG | `cnpg-system` | PostgreSQL cluster operator |
| Velero | `velero` | Backup / restore agent |
| Harbor | `harbor` | Container registry (stateful; PVCs restored via Velero in Phase 3) |
| Renovate | `renovate` | Dependency update automation |

### 2.3 — Verify Velero Is Ready

Velero must be available before restoring backups in Phase 3.

```bash
kubectl get pods -n velero
velero get backup-locations
```

The `default` backup storage location must show `Available`. If it shows `Unavailable`, check that ESO has synced the `cloud-credentials` secret in the `velero` namespace:

```bash
kubectl get externalsecret -n velero
kubectl get secret cloud-credentials -n velero
```

---

## Phase 3 — Velero Restore

### What Velero Backs Up

The Velero schedule (`kubernetes/infra/velero/overlays/default/backup-schedule.yaml`) runs daily at 07:00 UTC. It captures **Kubernetes object manifests** for `deployments`, `pods`, `persistentvolumes`, `persistentvolumeclaims`, and `namespaces`. File-system backup is off by default (`defaultVolumesToFsBackup: false`), but pod volumes are still included when explicitly annotated with `backup.velero.io/backup-volumes`.

For workloads/PVCs that use `synology-retain` or `nfs-csi-retain` (both `reclaimPolicy: Retain`), the underlying NAS data persists across cluster rebuilds. Velero's role is to restore the PVC/PV binding and Deployment objects so those workloads can re-attach to the same NAS volumes. Workloads using storage classes with `reclaimPolicy: Delete` should not assume underlying data persistence.

### Namespaces Covered

| Namespace | Contents / Notes |
|-----------|-----------------|
| `actual-budget` | Deployment, PVC |
| `grimmory` | Deployment, MariaDB PVC, data PVCs, NFS book-library PV/PVC |
| `harbor` | All Harbor PVCs: registry (50Gi), database (5Gi), jobservice (1Gi), redis (1Gi), trivy (5Gi) |
| `home-assistant` | Deployment, PVC |
| `immich` | Deployment, NFS photo library PV/PVC |
| `karakeep` | Deployment, PVCs (app + meilisearch) |
| `llm` | Open WebUI deployment, PVC |
| `media` | All *arr deployments + Jellyfin PVCs, NFS media/downloads PV/PVC |
| `n8n` | Deployment, PVC (database backed up separately via CNPG) |
| `navidrome` | Deployment, config PVC (1Gi), NFS music PV/PVC |
| `paperless` | Deployment, PVCs (database backed up separately via CNPG) |
| `syncthing` | Deployment, config PVC (1Gi), NFS sync-data PV/PVC |
| `zotero` | Deployment, PVC (10Gi) |

> **Note:** The `monitoring` namespace is intentionally excluded. Prometheus metrics are re-scraped after recovery, and Loki/Grafana/Uptime Kuma configurations are trivial to restore or rebuild.

### 3.1 — List Available Backups

```bash
velero get backups
```

Backups are retained for 10 days (240h TTL). Use the most recent backup name in the steps below.

### 3.2 — Verify annotated pod-volume backups

Before restore, confirm whether the selected backup captured any annotated pod volumes:

```bash
velero backup describe <backup-name> --details

# Check PodVolumeBackup objects created for that backup
kubectl get podvolumebackups -n velero \
  -l velero.io/backup-name=<backup-name>
```

If no PodVolumeBackup objects are listed, the backup contains only Kubernetes objects/PVC/PV manifests for this schedule (which is expected unless workloads are annotated with `backup.velero.io/backup-volumes`).

### 3.3 — Restore All Covered Namespaces

```bash
velero restore create --from-backup <backup-name>
```

To restore a single namespace only:

```bash
velero restore create \
  --from-backup <backup-name> \
  --include-namespaces actual-budget
```

### 3.4 — Monitor Restore Progress

```bash
velero restore get
velero restore describe <restore-name> --details
```

Wait until the restore shows `Completed`. Then verify PVCs are `Bound`:

```bash
kubectl get pvc -A | grep -v Bound
```

All PVCs must be `Bound` before proceeding. If a PVC is `Pending`, see [Velero PVC troubleshooting](#velero-restore-fails-for-pvcs).

---

## Phase 4 — CNPG Database Recovery

CNPG 1.27.0 `bootstrap.recovery` bootstraps a **new Cluster** from a backup; it is not an in-place restore. Changing `spec.bootstrap` on an already initialized Cluster—including changing it from `initdb` to `recovery`—does not restore that Cluster's data. Do not make that change or reconcile a recovery bootstrap onto an initialized Cluster as a restore. See the [CNPG 1.27 recovery documentation](https://cloudnative-pg.io/docs/1.27/recovery/) for the version-specific behavior.

The inventory below lists the repository's existing Cluster manifests; these are not recovery-mode manifests. App database resources are managed through `apps-production`. Authentik has a dedicated `authentik-production` Kustomization, separate from `infra-production`, which must remain suspended during recovery. This guide does not provide or authorize applying recovery settings to an existing Cluster.

This repository does not have a validated replacement-Cluster name, service, or cutover runbook. After the read-only backup and ObjectStore checks below, **stop**. Do not create, delete, or replace any Cluster, PVC, or database data until an explicit recovery plan covers a separate recovery Cluster, a unique WAL archive `serverName`, data verification, application database service/host cutover, and preservation or planned retirement of the original data.

### Cluster Inventory

| Cluster | Namespace | Barman Object Store | Azure Blob Path | Existing Cluster manifest (inventory) |
|---------|-----------|--------------------|-----------------|--------------------------|
| `immich-db` | `immich` | `immich-backup-storage` | `lhshomelabbackup/immich` | `kubernetes/apps/immich/base/db.yaml` |
| `n8n-db` | `n8n` | `n8n-backup-storage` | `lhshomelabbackup/n8n` | `kubernetes/apps/n8n/base/db/db.yaml` |
| `paperless-db` | `paperless` | `paperless-backup-storage` | `lhshomelabbackup/paperless` | `kubernetes/apps/paperless-ngx/base/db.yaml` |
| `commafeed-db` | `commafeed` | `commafeed-backup-storage` | `lhshomelabbackup/commafeed` | `kubernetes/apps/commafeed/base/db.yaml` |
| `litellm-db` | `llm` | `litellm-backup-storage` | `lhshomelabbackup/litellm` | `kubernetes/apps/litellm/base/db.yaml` |
| `coder-db` | `coder` | `coder-backup-storage` | `lhshomelabbackup/coder` | `kubernetes/apps/coder/base/db.yaml` |
| `authentik-db` | `authentik` | `authentik-backup-storage` | `lhshomelabbackup/authentik` | `kubernetes/infra/authentik/base/db/cluster.yaml` |
| `life-in-the-uk-quiz-db` | `life-in-the-uk-quiz` | `life-in-the-uk-quiz-backup-storage` | `lhshomelabbackup/life-in-the-uk-quiz` | `kubernetes/apps/life-in-the-uk-quiz/base/db.yaml` |

### 4.1 — Pre-flight: Verify Barman Backups Exist

Before CNPG creates a cluster, verify that barman backups are available for each database.

Use Azure Blob checks first (works even when no CNPG pod exists yet):

```bash
# Returns 1 when at least one base backup exists, 0 when none exists.
az storage blob list \
  --auth-mode login \
  --account-name lhshomelabbackup \
  --container-name immich \
  --prefix immich-db-backup/base/ \
  --num-results 1 \
  --query 'length(@)' -o tsv

# Repeat with each container/server pair from the Cluster Inventory table, e.g.:
#   n8n + n8n-db-backup
#   paperless + paperless-db-backup
#   commafeed + commafeed-db-backup
#   litellm + litellm-db-backup
#   coder + coder-db-backup
#   authentik + authentik-db-backup
#   life-in-the-uk-quiz + life-in-the-uk-quiz-db-backup
```

If a CNPG pod already exists, you can also verify from inside the cluster:

```bash
kubectl exec -it <cluster-name>-1 -n <namespace> -- \
  barman-cloud-backup-list --format json \
  lhshomelabbackup/<container> <server-name>
```

If no barman backup can be confirmed for a database that needs recovery, stop. Do not use `initdb` as a recovery substitute or initialize a Cluster and later change its bootstrap to `recovery`. Step 4.3 explains this boundary.

### 4.2 — Verify ObjectStore and Secrets Exist

Before a planned recovery Cluster can be created, the `ObjectStore` resource and its backing secret (synced by ESO) must exist in the namespace. The existing app database resources are managed through `apps-production`. Authentik's dedicated Kustomization remains suspended; do not resume it or use ordinary infra reconciliation to create Authentik resources during recovery.

```bash
# Check for each namespace that needs recovery, e.g. immich:
kubectl get objectstore -n immich
kubectl get secret -n immich | grep backup
```

If the `ObjectStore` or its secret is missing, stop. Resolve the missing prerequisite through an approved operations procedure before any recovery plan proceeds.

### 4.3 — No Backup or Fresh-Cluster Boundary

If no prior barman backup can be confirmed, there is nothing for CNPG recovery to restore. For a database that needs recovery, stop here; do not initialize a replacement or change an initialized Cluster's bootstrap in an attempt to restore it. `initdb` is only for deliberate first-time provisioning when no prior database data needs recovery. A later backup does not make changing that same initialized Cluster to `bootstrap.recovery` an in-place restore.

### 4.4 — Recovery Progress and Cutover

This repository does not define a validated replacement-Cluster name, service, or cutover process. Do not reconcile a recovery configuration to an existing Cluster or proceed from this guide to create or replace a Cluster. An explicit per-database recovery plan must first define the separate recovery Cluster and its unique WAL archive `serverName`, how restored data will be verified, how the application database service/host will be cut over, and how the original data will be preserved or intentionally retired. The plan must use `apps-production` for app database resources. Authentik must remain excluded from `infra-production` and its dedicated Kustomization suspended during this process; follow the documented stop boundary rather than attempting a fresh `initdb`.

### 4.5 — Data Verification Requirement

Data verification must be defined for the specific database and completed on the separate recovery Cluster before any application cutover. A generic healthy Cluster status or table-count query is not sufficient proof that the required data was restored.

---

## Phase 5 — Reconcile Monitoring

With infrastructure ready and PVCs restored via Velero, bring up the monitoring stack:

```bash
flux resume kustomization monitoring-production
flux reconcile kustomization monitoring-production --with-source
flux get kustomizations monitoring-production --watch
```

This deploys (all in the `monitoring` namespace):

| Component | Description |
|-----------|-------------|
| Prometheus | Metrics collection — data re-scraped automatically from targets |
| Grafana | Dashboards and alerts — configure once after cluster is up |
| Loki | Log aggregation — logs will be re-collected as workloads come back online |
| Alloy | Log/metric collection agent |
| Uptime Kuma | Uptime monitoring — trivial to reconfigure monitors |

---

## Phase 6 — Reconcile Applications

This phase can also reconcile CNPG Cluster manifests. Do not run it for database recovery until an explicit recovery plan is complete, the separate recovery Cluster is verified, and the application service/host cutover is ready. With those conditions met and infrastructure, databases, and monitoring in place, allow Flux to reconcile applications:

```bash
flux resume kustomization apps-production
flux reconcile kustomization apps-production --with-source
flux get kustomizations apps-production --watch
```

Applications in namespaces restored by Velero (Phase 3) will find their PVCs already `Bound`. Applications backed by CNPG databases may be reconciled only after the separate recovery Cluster has been verified and the application's database service/host cutover has been completed under an explicit recovery plan. The remaining stateless services (e.g. `commafeed`, `coder`, `life-in-the-uk-quiz`, `litellm`) will be deployed fresh from Git; any database data that needs recovery requires the same separate, approved recovery plan.

---

## Verification Checklist

After all phases are complete, verify the cluster health:

```bash
# All pods running (no Pending/CrashLoopBackOff)
kubectl get pods -A | grep -v -E 'Running|Completed'

# All CNPG clusters healthy
kubectl get cluster -A

# All Flux kustomizations ready
flux get kustomizations

# Velero restore status
velero restore get

# All PVCs bound
kubectl get pvc -A | grep -v Bound

# Certificate health
kubectl get certificates -A

# Ingress routes
kubectl get ingressroute -A
```

---

## Troubleshooting

### External Secrets not syncing

Check that `azure-sp-secret` exists in the `external-secrets` namespace with the correct keys (`ClientID`, `ClientSecret`). Then force a sync on the affected ExternalSecret:

```bash
kubectl get externalsecret -A
kubectl annotate externalsecret -n <namespace> <name> \
  force-sync=$(date +%s) --overwrite
```

### CNPG cluster stuck in `Recovering`

Check cluster events and the primary pod logs:

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

Velero backs up PVC/PV object manifests by default in this schedule; file-system backup runs only for pod volumes explicitly annotated with `backup.velero.io/backup-volumes`. If a PVC is restored but shows `Pending`, check that the `synology-retain` storage class is available and the Synology CSI driver is running:

```bash
kubectl get storageclass
kubectl get pods -n synology-csi
```

If the PV was using a static `volumeName` reference, ensure the PV manifest was restored and the NAS volume still exists. Re-apply the PV/PVC manually if Velero's restore missed them:

```bash
kubectl apply -f kubernetes/apps/<app>/base/pvc.yaml
```

If you expected file-system volume restore for a workload, verify that the source pod had `backup.velero.io/backup-volumes` and that PodVolumeBackup records exist for the selected backup:

```bash
velero backup describe <backup-name> --details
kubectl get podvolumebackups -n velero \
  -l velero.io/backup-name=<backup-name>
```
