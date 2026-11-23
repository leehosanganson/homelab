# Authentik SSO

Use the configured HTTPS Ingress for all Authentik single sign-on (SSO) access in this runbook. Replace `<authentik-host>` with `authentik.homelab.leehosanganson.dev`, the host in the [default chart values](../../kubernetes/infra/authentik/overlays/default/values.yaml). The values enable the Ingress with class `traefik`, TLS secret `authentik-tls`, and existing `letsencrypt-cloudflare` DNS-01 ClusterIssuer.

## Existing installation: sign in and troubleshoot HTTPS

1. Confirm the Kubernetes context with `kubectl config current-context`. From a trusted local network (LAN) client, confirm the hostname resolves to the expected LAN Traefik load balancer. Open `https://<authentik-host>/` and verify that the regular sign-in page loads with a trusted certificate for that hostname. Do not bypass certificate validation.
2. If the page does not load, inspect the matching layer before changing anything:
   - **Missing Ingress or wrong routing:** Check that `infra-production` and the `authentik` HelmRelease are Ready. Check the Ingress host, class, TLS secret, issuer annotation, and backend. If the backend returns an error, check the server pods and whether the Ingress backend Service has ready endpoints.
     ```bash
     kubectl get kustomizations.kustomize.toolkit.fluxcd.io infra-production -n flux-system
     kubectl get helmreleases.helm.toolkit.fluxcd.io authentik -n authentik
     kubectl describe ingress -n authentik
     kubectl get pods,svc,endpointslices -n authentik
     ```
   - **Certificate missing, expired, or untrusted:** Check the certificate's Ready condition and events; if issuance is pending, inspect cert-manager's Orders and Challenges. If the certificate is Ready but the browser sees the wrong one, recheck LAN DNS and the Ingress host and TLS secret. The issuer manages temporary DNS-01 challenge records; do not create permanent DNS records or change Cloudflare Tunnel routing to fix LAN access.
     ```bash
     kubectl describe certificates.cert-manager.io authentik-tls -n authentik
     kubectl get orders.acme.cert-manager.io,challenges.acme.cert-manager.io -n authentik
     ```
3. Once HTTPS works, verify sign-in with a local administrator account independent of external login sources, and verify its recovery path. Stop access changes until both are verified.
   - **If sign-in and recovery are verified:** Keep recovery credentials in the approved secret store outside Git and continue.
   - **If local administrator sign-in works but the recovery path cannot be verified:** Keep access changes blocked. Escalate to the responsible Authentik operator and database owner to validate the approved recovery procedure for the installed version and confirm the recovery credentials in the approved secret store. With the database owner, verify a recent Authentik backup as described in [Verify an Authentik backup](#verify-an-authentik-backup). The database owner must compare the verified backup's timestamp against the approved recovery point objective (RPO) or maximum backup age. If no approved freshness threshold exists or the backup is older than the threshold allows, stop and obtain an approved recovery plan before taking any recovery action. Do not attempt recovery until the procedure, credentials, and backup are verified.
   - **If no local administrator sign-in can be verified:** Keep existing access restrictions and tighten them through approved controls if needed. Do not grant or broaden access, use the fresh-install setup path, or reinitialize or manually alter the database. Escalate to the responsible Authentik operator and database owner for the approved recovery procedure for the installed version. With the database owner, verify a recent Authentik backup as described in [Verify an Authentik backup](#verify-an-authentik-backup). The database owner must compare the verified backup's timestamp against the approved recovery point objective (RPO) or maximum backup age. If no approved freshness threshold exists or the backup is older than the threshold allows, stop and obtain an approved recovery plan before taking any recovery action. Do not attempt recovery if the backup or procedure cannot be verified.

**Warning:** These checks verify LAN access only. They do not establish external reachability through Cloudflare Tunnel. Do not change Tunnel routes as part of this runbook.

## Fresh install: bootstrap the first administrator

1. Confirm the target Kubernetes context and check which revision Flux tracks or will track. There is no separate Authentik Kustomization: [`infra-production`](../../fluxcd/clusters/production/infra.yaml) can reconcile automatically. **Both gates must pass before Flux bootstrap, source tracking, or reconciliation can apply the Authentik overlay:** verify the setup-endpoint restrictions below and complete the database, PVC, and backup data preflight in step 2. A check just before a manual reconcile is not enough.
   - **If `infra-production` already tracks a revision with the overlay and you cannot prevent automatic reconciliation:** Treat the setup endpoint as potentially reachable and escalate immediately to the responsible production Flux operator. The [PR branch testing workflow](workflows-testing-validation.md#test-a-pr-branch-in-cluster-via-fluxcd) switches the shared source for all Kustomizations; it is not an Authentik-only containment procedure. Do not switch the shared source or remove the overlay ad hoc. Ask the operator to contain automatic application of the overlay through a reviewed plan that accounts for pruning, as required by the [Flux recovery gate](cluster-recovery.md#phase-1--bootstrap-flux). Do not trigger reconciliation, reinitialize the database, or continue setup until the operator verifies containment and completes both gates.
   - **Setup-endpoint gate:** Put approved access restrictions in place and verify that only intended operators can reach `/if/flow/initial-setup/` from the moment the Ingress goes live. LAN DNS and TLS checks alone do not verify who can reach it. Do not open the setup endpoint while access is uncertain.
2. **Data preflight gate:** Check for any existing Authentik CloudNativePG (CNPG) Cluster or persistent volume claim (PVC), and check the [read-only backup inventory](cluster-recovery.md#41--pre-flight-verify-barman-backups-exist) even if no Cluster is visible.
   ```bash
   kubectl get clusters.postgresql.cnpg.io,pvc -A
   ```
   **Stop if an Authentik Cluster, PVC, prior backup, or other database data exists, or if you cannot verify the data state.** The normal overlay uses `initdb`; do not reconcile it to recover or reinitialize data. See [CNPG recovery](#cnpg-recovery).
3. Verify that CNPG and the External Secrets Operator are healthy. Confirm the required Azure Key Vault entries through the approved secure workflow, without printing their values:
   - `authentik-secret-key`: long-lived `AUTHENTIK_SECRET_KEY`; preserve it across upgrades and restores.
   - `authentik-db-username` and `authentik-db-password`: database credentials; the username must be `authentik`.
   - `homelab-backup-storageaccount-name` and `authentik-blob-sas`: backup storage account and valid HTTPS-only SAS token for the `authentik` container with `racwdl` permissions.
   Stop if any prerequisite is missing or cannot be verified.
4. Once both gates and the other prerequisites pass, review the effective values and install the default overlay through the approved Flux workflow for `infra-production`. Keep the configured HTTPS Ingress enabled. Confirm `authentik-env-external`, `authentik-db-env-external`, and `authentik-backup-env-external` are Ready, `authentik-db` is healthy, and the Authentik server and worker pods are Ready.
   ```bash
   kubectl get externalsecrets.external-secrets.io,clusters.postgresql.cnpg.io,pods -n authentik
   ```
5. From a trusted LAN client, verify the Ingress DNS and TLS checks in [Existing installation](#existing-installation-sign-in-and-troubleshoot-https). With the approved access restrictions still in place, open `https://<authentik-host>/if/flow/initial-setup/` through the Ingress, including the trailing slash. Set the first administrator's password, verify regular sign-in, and confirm access to the approved recovery procedure and credentials. If readiness, HTTPS, or setup fails, stop and diagnose it; do not rerun installation or reinitialize the database to fix it.
6. [Verify the first CNPG backup](#verify-an-authentik-backup) before changing Application access.

## Verify an Authentik backup

The scheduled backup runs daily at 03:00 UTC.

```bash
kubectl get backups.postgresql.cnpg.io -n authentik \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,BACKUP_ID:.status.backupId,STARTED_AT:.status.startedAt'
```

Require phase `completed` and a backup ID. With the approved read-only Azure identity, list blob names in the `authentik` container under `authentik-db-backup/base/<backup-id>/` and confirm both `backup.info` and `data.tar.gz` exist for that exact ID. Stop before granting access if verification fails. File presence does not prove that a restore works.

## Rotate the backup SAS

1. Start well before the time-limited shared access signature (SAS) expires (for example, 30 days ahead). Issue a time-limited replacement scoped to the `authentik` container with HTTPS-only access and `racwdl` permissions. Update `authentik-blob-sas` in Azure Key Vault through the approved secure workflow. Do not print the token or put it in logs or Git.
2. In namespace `authentik`, wait for the source ExternalSecret `authentik-backup-env-external` to report Ready with a `status.refreshTime` later than the Key Vault update. It syncs the SAS to key `blob-sas` in the target Secret `authentik-backup-env`. Record the refresh time without reading or printing the Secret value.
3. The [repo-pinned Barman Cloud plugin v0.7.0](../../kubernetes/infra/cloudnativepg/barman-cloud-plugin.yaml) caches Secret reads for 10 seconds and reads the Secret before invoking Barman. A scheduled backup can report a start time after the wait even if the plugin loaded cached credentials before the wait ended. Do not use a scheduled backup to verify rotation. After recording the refresh time, wait at least 15 seconds and record when the cache wait ended in UTC.
4. Only after the wait, confirm the Kubernetes context and create a new CNPG `Backup`. Generate `BACKUP_NAME` from the current UTC timestamp. Use `kubectl create` so a name collision fails rather than updating an object. Never reapply an existing `Backup`.
   ```bash
   BACKUP_NAME="authentik-sas-check-$(date -u +%Y%m%d%H%M%S)"
   kubectl create -f - <<EOF
   apiVersion: postgresql.cnpg.io/v1
   kind: Backup
   metadata:
     name: ${BACKUP_NAME}
     namespace: authentik
   spec:
     cluster:
       name: authentik-db
     method: plugin
     pluginConfiguration:
       name: barman-cloud.cloudnative-pg.io
   EOF
   ```
5. Verify that exact `Backup` object:
   ```bash
   kubectl get backups.postgresql.cnpg.io "$BACKUP_NAME" -n authentik \
     -o custom-columns='CREATED_AT:.metadata.creationTimestamp,STARTED_AT:.status.startedAt,PHASE:.status.phase,BACKUP_ID:.status.backupId'
   ```
   Require both `metadata.creationTimestamp` and `status.startedAt` to be strictly later than the recorded cache-wait end, phase `completed`, and a nonempty `status.backupId`. Use the [read-only Azure inventory procedure](cluster-recovery.md#41--pre-flight-verify-barman-backups-exist) with `--auth-mode login` to list blob names in container `authentik` under `authentik-db-backup/base/<backup-id>/`, using that object's backup ID. List names instead of using the one-result count in the inventory example. Confirm that both exact blobs, `authentik-db-backup/base/<backup-id>/backup.info` and `authentik-db-backup/base/<backup-id>/data.tar.gz`, exist. Do not use or print the SAS for this check. If refresh or backup verification fails, investigate before expiry; do not treat the rotation as complete.

## Grant or revoke Application access

1. Verify [administrator sign-in and recovery](#existing-installation-sign-in-and-troubleshoot-https) before changing access. Confirm all three ExternalSecrets are Ready and [verify a recent CNPG backup](#verify-an-authentik-backup). Verify each user's identity, then add or remove the user in the approved access group as authorized.
2. In the Authentik admin UI, review the Application's policy, group, and user bindings. **An Application with no bindings allows access by default.** Bind the approved group before opening access. Review the binding evaluation mode and check that no other binding grants access outside that group. Never remove the only binding from a live Application to revoke access or roll back a change.
3. Test the Application in separate clean browser sessions. Verify that an approved member reaches protected content, while a signed-in nonmember and a signed-out visitor do not. For revocations, check whether existing application sessions still work and revoke them if required. If denial fails or is unclear, keep or take the affected route offline through the approved change workflow. Restore only a known access-controlled configuration and retest before reopening it.

## CNPG recovery

Follow [Cluster Recovery: CNPG Database Recovery](cluster-recovery.md#phase-4--cnpg-database-recovery). CNPG `bootstrap.recovery` creates a new Cluster; it is not an in-place restore. Do not reconcile the normal `initdb` overlay or remove Authentik from Flux inventory without an approved recovery plan: Flux can prune removed resources. Preserve the original database, PVCs, backups, and Key Vault values.

## References

- [Authentik first steps](https://docs.goauthentik.io/install-config/first-steps/)
- [Authentik policy bindings](https://docs.goauthentik.io/customize/policies/bindings/)
