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
3. Once HTTPS works, verify sign-in with a local administrator account independent of external login sources. Keep its recovery credentials in the approved secret store outside Git. If sign-in fails, use the approved administrator recovery procedure for the installed version. Stop access changes if administrator sign-in or recovery cannot be verified. Do not open the initial setup flow or reinitialize the database on an existing installation.

**Warning:** These checks verify LAN access only. They do not establish whether the unverified external Cloudflare Tunnel route permits public access to Authentik. Do not change Tunnel exposure as part of this runbook.

## Fresh install: bootstrap the first administrator

1. Confirm the target Kubernetes context. Before applying or reconciling the normal overlay, check for any existing Authentik CloudNativePG (CNPG) Cluster or persistent volume claim (PVC), and check the [read-only backup inventory](cluster-recovery.md#41--pre-flight-verify-barman-backups-exist) even if no Cluster is visible.
   ```bash
   kubectl get clusters.postgresql.cnpg.io,pvc -A
   ```
   **Stop if an Authentik Cluster, PVC, prior backup, or other database data exists, or if you cannot verify the data state.** The normal overlay uses `initdb`; do not reconcile it to recover or reinitialize data. See [CNPG recovery](#cnpg-recovery).
2. Verify that CNPG and the External Secrets Operator are healthy. Confirm the required Azure Key Vault entries through the approved secure workflow, without printing their values:
   - `authentik-secret-key`: long-lived `AUTHENTIK_SECRET_KEY`; preserve it across upgrades and restores.
   - `authentik-db-username` and `authentik-db-password`: database credentials; the username must be `authentik`.
   - `homelab-backup-storageaccount-name` and `authentik-blob-sas`: backup storage account and valid HTTPS-only SAS token for the `authentik` container with `racwdl` permissions.
   Stop if any prerequisite is missing or cannot be verified.
3. Review the effective values and install the default overlay through the approved Flux workflow for `infra-production`; there is no separate Authentik Kustomization. Keep the configured HTTPS Ingress enabled. Confirm `authentik-env-external`, `authentik-db-env-external`, and `authentik-backup-env-external` are Ready, `authentik-db` is healthy, and the Authentik server and worker pods are Ready.
   ```bash
   kubectl get externalsecrets.external-secrets.io,clusters.postgresql.cnpg.io,pods -n authentik
   ```
4. From a trusted LAN client, verify the Ingress DNS and TLS checks in [Existing installation](#existing-installation-sign-in-and-troubleshoot-https) before entering credentials. **Before opening the initial setup endpoint, use approved network controls to verify that only intended operators can reach it.** LAN validation does not establish whether the endpoint is reachable publicly or externally through Cloudflare Tunnel. If the reachability scope is unknown or includes anyone other than intended operators, stop and resolve it without changing Cloudflare Tunnel routes. Only after this check passes, open `https://<authentik-host>/if/flow/initial-setup/` through the Ingress, including the trailing slash. Set the first administrator's password, verify regular sign-in, and confirm access to the approved recovery procedure and credentials. If readiness, HTTPS, or setup fails, stop and diagnose it; do not rerun installation or reinitialize the database to fix it.
5. Before changing Application access, verify the first CNPG backup. The scheduled backup runs daily at 03:00 UTC.
   ```bash
   kubectl get backups.postgresql.cnpg.io -n authentik \
     -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,BACKUP_ID:.status.backupId,STARTED_AT:.status.startedAt'
   ```
   Require phase `completed` and a backup ID. With the approved read-only Azure identity, list blob names in the `authentik` container under `authentik-db-backup/base/<backup-id>/` and confirm both `backup.info` and `data.tar.gz` exist for that exact ID. Stop before granting access if verification fails. File presence does not prove that a restore works.

## Grant or revoke Application access

1. Verify [administrator sign-in and recovery](#existing-installation-sign-in-and-troubleshoot-https) before changing access. Confirm all three ExternalSecrets are Ready and a recent CNPG backup is verified as described in the fresh-install checks. Verify each user's identity, then add or remove the user in the approved access group as authorized.
2. In the Authentik admin UI, review the Application's policy, group, and user bindings. **An Application with no bindings allows access by default.** Bind the approved group before opening access. Review the binding evaluation mode and check that no other binding grants access outside that group. Never remove the only binding from a live Application to revoke access or roll back a change.
3. Test the Application in separate clean browser sessions. Verify that an approved member reaches protected content, while a signed-in nonmember and a signed-out visitor do not. For revocations, check whether existing application sessions still work and revoke them if required. If denial fails or is unclear, keep or take the affected route offline through the approved change workflow. Restore only a known access-controlled configuration and retest before reopening it.

## CNPG recovery

Follow [Cluster Recovery: CNPG Database Recovery](cluster-recovery.md#phase-4--cnpg-database-recovery). CNPG `bootstrap.recovery` creates a new Cluster; it is not an in-place restore. Do not reconcile the normal `initdb` overlay or remove Authentik from Flux inventory without an approved recovery plan: Flux can prune removed resources. Preserve the original database, PVCs, backups, and Key Vault values.

## References

- [Authentik first steps](https://docs.goauthentik.io/install-config/first-steps/)
- [Authentik policy bindings](https://docs.goauthentik.io/customize/policies/bindings/)
