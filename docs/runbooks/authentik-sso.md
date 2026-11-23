# Authentik SSO

Use this runbook to operate Authentik single sign-on (SSO), verify local network (LAN) access, and manage application access. The integration patterns are for approved onboarding; they do not describe deployed integrations.

## Preflight for an existing installation

1. Confirm the Kubernetes context and the scope of the approved operation.
2. From the LAN, open `https://<authentik-host>` using the host configured in the Authentik Ingress. Verify administrator sign-in and confirm access to the approved recovery procedure and credentials. Keep a local administrator account independent of external login sources and store its recovery credentials in the approved secret store outside Git.
3. If the Ingress is unavailable, use this loopback-only port-forward from a trusted workstation:
   ```bash
   kubectl port-forward --address 127.0.0.1 -n authentik svc/authentik-server 9000:80
   ```
   Open the regular sign-in page at `http://127.0.0.1:9000/`. This bypasses the Ingress, not Authentik sign-in. Stop the port-forward with Ctrl-C when done. If sign-in fails, follow the approved administrator recovery procedure for the installed version. Do not open the initial setup flow or reinitialize the database.
4. Stop before changing access if administrator sign-in or recovery cannot be verified. Confirm the ExternalSecrets are Ready and [verify a recent Authentik backup](#verify-an-authentik-backup) before proceeding.

## Required Azure Key Vault values

Confirm these entries before a fresh install. For routine operations, do not recreate them. Create or update values only through the approved secure Key Vault workflow; never print, log, commit, or share them in chat.

| Azure Key Vault entry | Kubernetes secret/key | Purpose |
|---|---|---|
| `authentik-secret-key` | `authentik-env` / `AUTHENTIK_SECRET_KEY` | Long-lived Authentik signing/encryption key. Preserve it across upgrades and restores. |
| `authentik-db-username` | `authentik-db-env` / `username` | CloudNativePG (CNPG) initial database owner; value must be `authentik`. |
| `authentik-db-password` | `authentik-db-env` / `password` | CNPG/Authentik database password. |
| `homelab-backup-storageaccount-name` | `authentik-backup-env` / `storage-account-name` | Existing shared backup storage account reference. |
| `authentik-blob-sas` | `authentik-backup-env` / `blob-sas` | HTTPS-only SAS token for the `authentik` container, with `racwdl` permissions and a 180-day lifetime. |

Start SAS renewal well before expiry (for example, 30 days ahead). Create a replacement with the same container scope, HTTPS-only access, and `racwdl` permissions. Update Key Vault securely. Wait for the `authentik-backup-env-external` ExternalSecret in the `authentik` namespace to report Ready with a `status.refreshTime` after the update, and record that refresh time. Then [verify a new backup](#verify-an-authentik-backup) that started after the refresh. An expired SAS stops database backups.

## Fresh install only

**Never repeat this procedure against an initialized installation or use it to recover data.** The Authentik chart's bundled PostgreSQL is disabled. The normal overlay creates a separate CNPG Cluster with `initdb`.

1. Confirm the target Kubernetes context. Check for any existing Authentik Cluster, persistent volume claim (PVC), or prior database data. Check the [read-only backup inventory](cluster-recovery.md#41--pre-flight-verify-barman-backups-exist), even if no Cluster is visible.
   ```bash
   kubectl get clusters.postgresql.cnpg.io,pvc -A
   ```
   If an Authentik Cluster, PVC, prior backup, or other database data exists, or you cannot verify the data state, stop and follow [CNPG recovery](#cnpg-recovery-and-infrastructure-rollback). Do not apply or reconcile the normal overlay.
2. Verify that CNPG and the External Secrets Operator are healthy and can access their required resources. Confirm all five Key Vault entries exist and are valid without printing their values. Stop if any prerequisite is missing or cannot be verified.
3. Use a reviewed bootstrap values configuration that sets `server.ingress.enabled: false`. The normal default overlay may enable the Ingress. Do not use it as-is for first-admin bootstrap; isolate bootstrap with the reviewed values. Before reconciling, render the GitOps manifests and the Authentik chart with the effective bootstrap values. Inspect both outputs and confirm there is no Authentik Ingress or other route exposing Authentik. Stop if any such route or any resource outside the approved bootstrap scope is present. Only then install through the approved Flux workflow with `infra-production`; there is no separate Authentik Kustomization.
4. Confirm the ExternalSecrets are Ready, `authentik-db` is initialized and healthy, and the Authentik server and worker pods are Ready. Stop and diagnose any failure; do not rerun bootstrap to fix it.
   ```bash
   kubectl get externalsecrets.external-secrets.io,clusters.postgresql.cnpg.io,pods -n authentik
   ```
5. From a trusted workstation, start a loopback-only port-forward:
   ```bash
   kubectl port-forward --address 127.0.0.1 -n authentik svc/authentik-server 9000:80
   ```
   Open `http://127.0.0.1:9000/if/flow/initial-setup/` with the trailing slash. Create the bootstrap administrator and verify sign-in and recovery. Use only the loopback port-forward for Authentik access through setup and first backup verification; keep the Ingress disabled.
6. [Verify the first completed CNPG backup and its base-backup files](#verify-an-authentik-backup). If setup or backup verification fails, stop before enabling the Ingress or onboarding. Do not delete or reinitialize the database. Stop the port-forward with Ctrl-C when done.
7. Only after administrator sign-in, recovery, and the first backup are verified, enable the LAN Ingress through a separate reviewed GitOps change. Run the [LAN Ingress and TLS checks](#authentik-lan-ingress-and-tls). Do not broaden external exposure or change Cloudflare Tunnel.

### Verify an Authentik backup

1. List Backup resources and check the phase of the backup you intend to verify:
   ```bash
   kubectl get backups.postgresql.cnpg.io -n authentik
   ```
   `authentik-backup-schedule` runs daily at 03:00 UTC. If you need a backup before the next run, and `authentik-manual-initial-backup` does not already exist, use the following for an approved on-demand backup during fresh installation. If the name exists, inspect that Backup instead of reapplying it.
   ```bash
   kubectl apply -f - <<'EOF'
   apiVersion: postgresql.cnpg.io/v1
   kind: Backup
   metadata:
     name: authentik-manual-initial-backup
     namespace: authentik
   spec:
     cluster:
       name: authentik-db
     method: plugin
     pluginConfiguration:
       name: barman-cloud.cloudnative-pg.io
   EOF
   ```
2. Set `BACKUP_NAME` to the exact Backup resource name and read its phase, backup ID, and start time:
   ```bash
   kubectl get backups.postgresql.cnpg.io "${BACKUP_NAME:?Set the Backup resource name}" -n authentik \
     -o custom-columns='PHASE:.status.phase,BACKUP_ID:.status.backupId,STARTED_AT:.status.startedAt'
   ```
   Require `status.phase` to be `completed` and `status.backupId` to be present. For SAS renewal, require this Backup's `status.startedAt` to be later than the recorded ExternalSecret refresh time. Do not use an older backup, even if it completed after the refresh.
3. Set `BACKUP_ID` to that Backup's `status.backupId` and `BACKUP_STORAGE_ACCOUNT` to the approved storage account name. List only that ID's base-backup directory using the approved read-only Azure identity:
   ```bash
   az storage blob list --auth-mode login --account-name "${BACKUP_STORAGE_ACCOUNT:?Set the backup storage account name}" \
     --container-name authentik --prefix "authentik-db-backup/base/${BACKUP_ID:?Set status.backupId from the selected Backup}/" \
     --query '[].name' -o tsv
   ```
   Confirm both `backup.info` and `data.tar.gz` exist directly under `authentik-db-backup/base/<backupId>/` for that exact ID. This verifies file presence, not that a restore works. If you cannot confirm the required status or either file, stop and resolve the backup or inventory access problem.

## Authentik LAN Ingress and TLS

Use the Authentik chart Ingress for LAN access at `https://<authentik-host>` through the LAN Traefik load balancer. The desired Ingress uses class `traefik`, TLS secret `authentik-tls`, and the existing `letsencrypt-cloudflare` DNS-01 ClusterIssuer. The issuer may create temporary challenge records. Do not manually create permanent DNS records or create or modify Cloudflare Tunnel routes.

1. Confirm the target context and use a LAN client for the DNS and HTTPS checks. Inspect the GitOps and Ingress resources without changing them:
   ```bash
   kubectl get kustomizations.kustomize.toolkit.fluxcd.io infra-production -n flux-system
   kubectl get helmreleases.helm.toolkit.fluxcd.io -n authentik
   kubectl get ingress -n authentik
   kubectl describe ingress -n authentik
   kubectl get certificates.cert-manager.io authentik-tls -n authentik
   ```
2. Confirm `infra-production`, the Authentik HelmRelease, and the certificate report Ready. Check that the Ingress matches the intended Authentik hostname, class, TLS secret, and issuer.
3. From the LAN, confirm the hostname resolves to the expected LAN load balancer and the regular sign-in page loads over HTTPS with a trusted certificate for that hostname. Do not bypass certificate validation or rerun initial setup. **Warning:** These checks verify LAN access only. They do not establish whether the unverified external Cloudflare Tunnel route permits public access to Authentik.
4. If any check fails, stop and diagnose the LAN path. Use the loopback-only fallback for administrator access rather than changing DNS or Tunnel routing.

## Manage users, groups, and application bindings

1. Complete the [existing-installation preflight](#preflight-for-an-existing-installation). Configure only approved login sources, and leave enrollment disabled or invitation-only.
2. Verify each user's identity in the Authentik admin UI before adding them to an approved group. The login source identifies the user; the application binding decides who gets access.
3. **An Authentik Application with no bindings allows access by default.** Before exposing the app, bind it to the approved group. Review the binding evaluation mode and confirm no other binding grants access outside that group.
4. Test with both an approved identity and a signed-in nonmember. If the nonmember can access the app or the result is unclear, keep it unavailable until the binding is fixed. Do not remove the only binding from a live app as a rollback.

## Choose an integration pattern

Before onboarding, complete the [preflight](#preflight-for-an-existing-installation) and [LAN checks](#authentik-lan-ingress-and-tls). Record the intended host, protected routes, approved group, application owner, and rollback plan. Keep normal user traffic off the service until the access checks pass.

### Native OpenID Connect (OIDC)

Use native OIDC when the service supports it and can enforce its own sessions and roles.

1. Create an Authentik OAuth2/OIDC provider and link it to an Application. Apply the approved group binding before enabling login. Use the client type required by the service and register its exact HTTPS callback as a strict redirect URI, such as `https://<service-host>/<oidc-callback-path>`. Use the callback path documented by the service, not a wildcard.
2. Use the provider's discovery document at `https://<authentik-host>/application/o/<application-slug>/.well-known/openid-configuration`. Verify the issuer matches the service configuration. Confirm the service can reach discovery, token, and signing-key endpoints over trusted TLS, and the browser can reach the authorization endpoint and return to the service callback. The callback must reach the service without requiring a session that the callback itself creates.
3. Deliver any client secret through the approved secret store. Verify secret synchronization without printing the value. Request only the claims and scopes the service needs.
4. Verify account linking, role mapping, logout, and session expiry. Keep a tested administrator recovery path before changing local login or enrollment. Confirm whether existing service sessions survive removal from the approved group and how to revoke those sessions if required.

### Proxy Provider and ForwardAuth

Use this pattern when Traefik must enforce browser sign-in in front of a service. Traefik asks the Authentik outpost to authorize each protected request before forwarding it to the backend.

1. Create an Authentik Proxy Provider in **Forward auth (single application)** mode with external host `https://<service-host>`. Link it to an Authentik Application, apply the approved group binding, and assign the provider to the intended outpost.
2. Attach the ForwardAuth middleware to the protected routes. Route `https://<service-host>/outpost.goauthentik.io/` directly to the assigned outpost without that middleware, so the callback can complete without a redirect loop. Verify the outpost route takes precedence over the backend route, uses a trusted certificate for the service host, and never serves backend content.
3. Limit direct backend access to approved ingress and internal callers. If the service uses identity headers, accept them only from the trusted proxy; do not trust client-supplied identity headers. Confirm the gate denies access if the outpost cannot authorize a request.

## Verify access before opening traffic

- **Native OIDC:** Use separate clean browser sessions. Verify that neither a signed-out user nor a signed-in nonmember receives protected content. The service may show its local login page first; an automatic redirect to Authentik is not required. Verify an approved user completes the OIDC callback and reaches the service. Check logout and retry the protected route.
- **ForwardAuth:** Use separate clean browser sessions. Verify that a signed-out user is redirected to Authentik and receives no protected content, and that a signed-in nonmember is denied without receiving protected content. Verify an approved user completes the outpost callback and reaches the service. Check logout and retry the protected route.
- **API and WebSocket:** Where present, verify authorized clients can use API routes and complete WebSocket upgrades. Verify unauthorized clients receive no protected response or WebSocket data. Browser redirects are not a substitute for supported API authentication.
- **Health checks:** Confirm probes still work. If a health route does not require login, restrict it to the intended callers and verify it exposes no protected content or broader route.
- **Backend and alternate paths:** From approved test locations, verify the ingress can reach the backend and unapproved callers cannot bypass authentication through another hostname, plain HTTP, or a direct Service or Pod address. Verify any approved alternate route enforces its intended access policy.

## Stop or roll back an integration

If access, callback, or bypass checks fail or are inconclusive, keep the service unavailable to normal users. If denial cannot be confirmed, take the affected route offline through the approved change workflow and verify it no longer serves protected content. Readiness alone does not prove access is enforced.

Restore only the last known working, access-controlled configuration. Never remove the only Application binding, detach ForwardAuth from a live protected route, or restore unauthenticated access as a fallback. Preserve account mappings and review active sessions before retiring an identity provider. Repeat the access checks before reopening traffic.

## CNPG recovery and infrastructure rollback

Do not remove Authentik from `infra-production` without a reviewed plan: Flux prunes resources removed from its inventory. Preserve the database, PVCs, backups, Key Vault values, and long-lived `AUTHENTIK_SECRET_KEY` during rollback.

CNPG `bootstrap.recovery` creates a **new Cluster**; changing `initdb` to `recovery` on an initialized Cluster does not restore it. Follow the read-only checks in [Cluster Recovery: CNPG Database Recovery](cluster-recovery.md#phase-4--cnpg-database-recovery), then stop until a replacement-cluster and cutover plan is approved. Keep the normal `initdb` overlay from reconciling during recovery. The plan must cover backup and write-ahead log availability, a separate archive name, restored data validation, database connection cutover, and preservation of the original data. Do not create, delete, or replace a Cluster, PVC, or data without that plan.

## References

- [Authentik Kubernetes installation](https://docs.goauthentik.io/install-config/install/kubernetes/) — chart installation and production database guidance.
- [Authentik first steps](https://docs.goauthentik.io/install-config/first-steps/) — initial admin, application/provider setup, and group-binding guidance.
- [Authentik OAuth2/OIDC provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/) — native OIDC provider configuration.
- [Authentik policy bindings](https://docs.goauthentik.io/customize/policies/bindings/) — application bindings and policy evaluation.
- [Authentik ForwardAuth](https://docs.goauthentik.io/add-secure-apps/providers/proxy/forward_auth/) — Proxy Provider modes and outpost routing.
