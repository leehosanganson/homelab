# Cluster Migration — K3s to Talos

Runbook for migrating the homelab Kubernetes platform from an existing K3s cluster to a new Talos cluster with minimal downtime, while preserving stateful workloads through retained storage classes, Velero object restore, and CNPG recovery from barman backups.

## 1) Overview and Phase Map

This migration is executed as a controlled cutover. Build and validate the Talos target first, then progressively restore state and switch traffic.

```
Phase 0: Preconditions + inventory + go/no-go
     ↓
Phase 1: Build Talos cluster + baseline checks
     ↓
Phase 2: Bootstrap Flux + staged suspend/reconcile
     ↓
Phase 3: Data/state migration (Velero + CNPG)
     ↓
Phase 4: Traffic and DNS cutover
     ↓
Phase 5: Validation gates
     ↓
Phase 6: Rollback (if triggered)
     ↓
Phase 7: Post-migration cleanup
```

### Migration principles

- Keep `infra-production` active; control timing by suspending/resuming `apps-production` and `monitoring-production`.
- Use Velero to restore Kubernetes objects/PVC bindings; persistent data remains on NAS for retain storage classes.
- Use CNPG `bootstrap.recovery` overlays for database recovery from barman unless a cluster has no historical backup.
- Perform DNS/Ingress cutover only after all gates pass.

---

## 2) Preconditions and Preflight Inventory / Go-No-Go

### 2.1 Required tooling and access

- `kubectl` (contexts for source K3s and target Talos)
- `flux` CLI
- `velero` CLI
- `talosctl`
- `az` CLI authenticated with access to:
  - Key Vault: `lhs-kubernetes-keyvault`
  - Blob account/container paths used by Velero and CNPG barman
- GitHub CLI (`gh`) for Flux bootstrap workflows if needed

### 2.2 Inventory checklist (capture before any production pause)

```bash
# Set contexts
export SRC_CTX="<k3s-context>"
export DST_CTX="<talos-context>"

# Snapshot source cluster health
kubectl --context "$SRC_CTX" get nodes -o wide
kubectl --context "$SRC_CTX" get kustomizations -A
kubectl --context "$SRC_CTX" get pods -A

# Snapshot ingress and DNS-relevant resources
kubectl --context "$SRC_CTX" get ingressroute -A
kubectl --context "$SRC_CTX" get svc -n traefik

# Snapshot storage classes and PVC state
kubectl --context "$SRC_CTX" get storageclass
kubectl --context "$SRC_CTX" get pvc -A

# Snapshot CNPG and Velero status
kubectl --context "$SRC_CTX" get cluster -A
velero --kubecontext "$SRC_CTX" get backups
```

### 2.3 Confirm backup recency

```bash
# Velero backups should include migration-critical namespaces
velero --kubecontext "$SRC_CTX" get backups

# Example CNPG base-backup existence check (repeat per DB from inventory)
az storage blob list \
  --auth-mode login \
  --account-name <backup-storage-account> \
  --container-name <db-container> \
  --prefix <server-name>/base/ \
  --num-results 1 \
  --query 'length(@)' -o tsv
```

### 2.4 Go / No-Go gate

Proceed only if all are true:

- Recent Velero backup exists and is readable.
- CNPG barman base backups exist for databases planned for recovery.
- Azure Key Vault credentials are retrievable (for ESO bootstrap secret).
- Retain storage classes expected by workloads are known (`synology-retain`, `nfs-csi-retain`) and available on target design.
- Migration window and rollback owner are confirmed.

---

## 3) Build Target Talos Cluster and Baseline Checks

Provision Talos control plane and workers using your IaC flow, then validate Kubernetes fundamentals before introducing Flux.

### 3.1 Cluster baseline checks

```bash
kubectl --context "$DST_CTX" get nodes -o wide
kubectl --context "$DST_CTX" get ns
kubectl --context "$DST_CTX" get crd | wc -l
```

### 3.2 Networking and storage baseline checks

```bash
# CNI / DNS baseline
kubectl --context "$DST_CTX" get pods -n kube-system

# Storage class readiness (must include retain classes used by apps)
kubectl --context "$DST_CTX" get storageclass
```

### 3.3 Baseline gate

Proceed only if:

- All Talos nodes are `Ready`.
- Core system pods are healthy.
- Required retain storage classes are present or will be created by infra reconcile.

---

## 4) Flux Bootstrap and Staged Reconcile / Suspend Strategy

Flux must be installed first, but app and monitoring reconciliation should be controlled to prevent races during restore.

### 4.1 Bootstrap Flux on Talos

```bash
# Run from repo root; script fetches token from Azure Key Vault
./fluxcd/bootstrap.sh

kubectl --context "$DST_CTX" get pods -n flux-system
flux --context "$DST_CTX" get kustomizations
```

### 4.2 Immediately suspend app + monitoring kustomizations

```bash
flux --context "$DST_CTX" suspend kustomization apps-production
flux --context "$DST_CTX" suspend kustomization monitoring-production
flux --context "$DST_CTX" get kustomizations
```

Keep `infra-production` active.

### 4.3 Seed ESO bootstrap credential and reconcile infra

```bash
kubectl --context "$DST_CTX" create namespace external-secrets

kubectl --context "$DST_CTX" create secret generic azure-sp-secret \
  --namespace=external-secrets \
  --from-literal=ClientID=<sp-client-id> \
  --from-literal=ClientSecret=<sp-client-secret>

flux --context "$DST_CTX" reconcile kustomization infra-production --with-source
flux --context "$DST_CTX" get kustomizations --watch
```

### 4.4 Infra gate

```bash
kubectl --context "$DST_CTX" get pods -n external-secrets
kubectl --context "$DST_CTX" get externalsecret -A

kubectl --context "$DST_CTX" get pods -n velero
velero --kubecontext "$DST_CTX" get backup-locations

kubectl --context "$DST_CTX" get pods -n traefik
kubectl --context "$DST_CTX" get storageclass
```

Proceed only if ESO, Velero, Traefik, CNPG operator, and CSI/storage stack are healthy.

---

## 5) Data/State Migration (Velero + CNPG) with Minimal Downtime Sequencing

Use this sequence to minimize write divergence.

### 5.1 Freeze write-heavy applications on source (downtime start)

At cutover start, stop or scale down write-heavy workloads in K3s source cluster to prevent split-brain writes during final restore/recovery window.

```bash
# Example: scale selected deployments down on source
kubectl --context "$SRC_CTX" -n <namespace> scale deploy/<name> --replicas=0

# Repeat for stateful/write-heavy services (databases remain managed by CNPG procedures)
```

### 5.2 Trigger final backup point (optional but recommended)

```bash
# Optional Velero on source for most recent object state
velero --kubecontext "$SRC_CTX" backup create pre-cutover-$(date +%Y%m%d-%H%M) \
  --include-namespaces <comma-separated-namespaces>

velero --kubecontext "$SRC_CTX" get backups
```

### 5.3 Restore Kubernetes objects/PVC bindings on target

```bash
velero --kubecontext "$DST_CTX" get backups

# Restore latest suitable backup
velero --kubecontext "$DST_CTX" restore create --from-backup <backup-name>

velero --kubecontext "$DST_CTX" restore get
velero --kubecontext "$DST_CTX" restore describe <restore-name> --details
```

### 5.4 Validate PVC attachment assumptions for retain classes

```bash
kubectl --context "$DST_CTX" get pvc -A
kubectl --context "$DST_CTX" get pv
kubectl --context "$DST_CTX" get storageclass
```

All required PVCs must be `Bound`. For this repo, retained NAS-backed classes (`synology-retain`, `nfs-csi-retain`) are expected to re-bind to preserved data paths.

### 5.5 Recover CNPG databases on target

With `apps-production` still suspended, verify each namespace has ObjectStore + backup secret before bringing apps.

```bash
kubectl --context "$DST_CTX" get objectstore -A
kubectl --context "$DST_CTX" get secret -A | grep backup
```

If required, force ESO sync for a namespace:

```bash
kubectl --context "$DST_CTX" annotate externalsecret -n <namespace> <name> \
  force-sync=$(date +%s) --overwrite
```

Then resume apps reconcile to let CNPG cluster recovery execute:

```bash
flux --context "$DST_CTX" resume kustomization apps-production
flux --context "$DST_CTX" reconcile kustomization apps-production --with-source

kubectl --context "$DST_CTX" get cluster -A -w
```

### 5.6 Minimal downtime gate

Proceed to traffic cutover only if:

- Velero restore is `Completed`.
- All critical PVCs are `Bound`.
- CNPG clusters report healthy state after recovery.
- App pods on target are running and passing readiness probes.

---

## 6) Traffic / DNS Cutover Strategy

Move traffic only after target is validated.

### 6.1 Pre-cutover checks

```bash
kubectl --context "$DST_CTX" get ingressroute -A
kubectl --context "$DST_CTX" get svc -n traefik
kubectl --context "$DST_CTX" get certificates -A
```

### 6.2 DNS switch

Update authoritative DNS records so application hostnames resolve to the Talos ingress endpoint.

```bash
# Placeholder commands (provider-specific)
# <dns-cli> record update <zone> <name> A <new-traefik-ip>
# <dns-cli> record update <zone> <name> CNAME <new-traefik-host>
```

Recommended:

- Lower TTL in advance (e.g., 60–300s) before cutover window.
- Apply DNS changes in batches: platform-critical first, then low-risk apps.

### 6.3 Cutover verification

```bash
kubectl --context "$DST_CTX" get ingressroute -A
curl -Ik https://<app-hostname>
```

After successful validation on Talos, keep source workloads scaled down.

---

## 7) Validation Checklist

Run after DNS cutover and again after one full reconciliation interval.

```bash
# Flux health
flux --context "$DST_CTX" get kustomizations

# Workload health
kubectl --context "$DST_CTX" get pods -A
kubectl --context "$DST_CTX" get pods -A | grep -v -E 'Running|Completed'

# Velero and storage
velero --kubecontext "$DST_CTX" restore get
kubectl --context "$DST_CTX" get pvc -A

# CNPG
kubectl --context "$DST_CTX" get cluster -A

# Ingress + TLS
kubectl --context "$DST_CTX" get ingressroute -A
kubectl --context "$DST_CTX" get certificates -A
```

Application-level checks (sample):

- Confirm login and key workflows for critical services.
- Verify recent records/files are present in migrated stateful apps.
- Confirm new writes persist on target storage.

---

## 8) Rollback Procedure and Trigger Points

Rollback should be fast, explicit, and reversible.

### 8.1 Trigger points (rollback decision)

Trigger rollback if any of the following persist beyond agreed threshold (for example, 15–30 minutes):

- Multiple critical services unavailable after DNS switch.
- CNPG recovery failure on critical database with no short-term fix.
- Widespread PVC bind failures on target.
- Ingress/TLS failure preventing access to core apps.

### 8.2 Rollback actions

1. Revert DNS records to source ingress endpoint.
2. Confirm source ingress routes are serving traffic.
3. Keep target apps paused for impacted namespaces to avoid divergent writes.

```bash
# Optional: suspend app reconciliation on target during rollback triage
flux --context "$DST_CTX" suspend kustomization apps-production

# Ensure source workloads are up (examples)
kubectl --context "$SRC_CTX" -n <namespace> scale deploy/<name> --replicas=<previous>
kubectl --context "$SRC_CTX" get pods -A
```

### 8.3 Rollback gate

Rollback is complete when:

- DNS resolves to source.
- Source app health checks pass.
- Users can access critical paths.

Document incident timeline and root cause before scheduling re-attempt.

---

## 9) Post-Migration Cleanup

After stable operation on Talos (for agreed observation window):

1. Confirm Flux in Talos tracks `main` and all kustomizations are healthy.
2. Remove temporary migration-only scale overrides and manual patches.
3. Decommission or quarantine K3s cluster access.
4. Re-enable normal backup schedules/alerts and verify green status.
5. Update operational docs with final ingress endpoints, node inventory, and lessons learned.

```bash
flux --context "$DST_CTX" get sources git -n flux-system
flux --context "$DST_CTX" get kustomizations
velero --kubecontext "$DST_CTX" get schedules
```

---

## 10) Troubleshooting

### Flux reconciling too early / racing restores

```bash
flux --context "$DST_CTX" suspend kustomization apps-production
flux --context "$DST_CTX" suspend kustomization monitoring-production
flux --context "$DST_CTX" get kustomizations
```

### External Secrets not syncing from Azure Key Vault

```bash
kubectl --context "$DST_CTX" get secret azure-sp-secret -n external-secrets
kubectl --context "$DST_CTX" get externalsecret -A
kubectl --context "$DST_CTX" annotate externalsecret -n <namespace> <name> \
  force-sync=$(date +%s) --overwrite
```

### Velero restore succeeds but PVCs remain Pending

```bash
kubectl --context "$DST_CTX" get pvc -A
kubectl --context "$DST_CTX" get pv
kubectl --context "$DST_CTX" get storageclass
kubectl --context "$DST_CTX" get pods -n synology-csi
```

Validate that retained classes and backing NAS volumes still exist and match expected PV/PVC references.

### CNPG cluster stuck in Recovering

```bash
kubectl --context "$DST_CTX" describe cluster <cluster-name> -n <namespace>
kubectl --context "$DST_CTX" logs <cluster-name>-1 -n <namespace> -c postgres
```

Common causes:

- Missing/invalid ObjectStore secret from ESO.
- Missing base backup in barman object store path.

### Traefik routes present but endpoint inaccessible

```bash
kubectl --context "$DST_CTX" get ingressroute -A
kubectl --context "$DST_CTX" get svc -n traefik
kubectl --context "$DST_CTX" get endpoints -A
kubectl --context "$DST_CTX" get certificates -A
```

Check DNS propagation, Traefik service exposure, and certificate readiness.
