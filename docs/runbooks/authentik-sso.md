# Homelab SSO: Authentik, Mini QR, and Karakeep

Use this runbook to bootstrap a new Authentik installation, verify LAN access, manage app access, or onboard Mini QR with Traefik ForwardAuth. Leave Karakeep OIDC inactive unless it is reviewed and approved separately.

## Preflight for an existing installation

1. Confirm the Kubernetes context and the scope of the approved operation.
2. From the LAN, open `https://authentik.homelab.leehosanganson.dev` and verify Authentik administrator sign-in and the administrator recovery path at the time of the operation. If the Ingress is unavailable, use the loopback-only port-forward in [Fresh install only](#fresh-install-only), but open the regular sign-in page at `http://127.0.0.1:9000/`, not the initial setup flow.
3. Stop before changing access or onboarding an app if administrator sign-in or recovery cannot be verified. Keep recovery credentials outside Git and keep the bootstrap administrator separate from social-login accounts.

## Required Azure Key Vault values

Confirm these entries before a fresh install. For routine operations, do not recreate them. Create or update values only through the approved secure Key Vault workflow; never print, log, commit, or share them in chat.

| Azure Key Vault entry | Kubernetes secret/key | Purpose |
|---|---|---|
| `authentik-secret-key` | `authentik-env` / `AUTHENTIK_SECRET_KEY` | Long-lived Authentik signing/encryption key. Preserve it across upgrades and restores. |
| `authentik-db-username` | `authentik-db-env` / `username` | CloudNativePG (CNPG) initial database owner; value must be `authentik`. |
| `authentik-db-password` | `authentik-db-env` / `password` | CNPG/Authentik database password. |
| `homelab-backup-storageaccount-name` | `authentik-backup-env` / `storage-account-name` | Existing shared backup storage account reference. |
| `authentik-blob-sas` | `authentik-backup-env` / `blob-sas` | HTTPS-only SAS token for the `authentik` container, with `racwdl` permissions and a 180-day lifetime. |

Start SAS renewal well before expiry (for example, 30 days ahead). Create a replacement with the same container scope, HTTPS-only access, and `racwdl` permissions. Update Key Vault securely, wait for the ExternalSecret to refresh and report Ready, then [verify a new backup](#verify-an-authentik-backup). An expired SAS stops database backups.

## Fresh install only

**Never repeat this procedure against an initialized installation or use it to recover data.** The Authentik chart's bundled PostgreSQL is disabled. The normal overlay creates a separate CNPG Cluster with `initdb`.

1. Confirm the target Kubernetes context. Check for any existing Authentik Cluster, persistent volume claim (PVC), or prior database data. Check the [read-only backup inventory](cluster-recovery.md#41--pre-flight-verify-barman-backups-exist), even if no Cluster is visible.
   ```bash
   kubectl get clusters.postgresql.cnpg.io,pvc -A
   ```
   If an Authentik Cluster, PVC, prior backup, or other database data exists, or you cannot verify the data state, stop and follow [CNPG recovery](#cnpg-recovery-and-infrastructure-rollback). Do not apply or reconcile the normal overlay.
2. Verify that CNPG and the External Secrets Operator are healthy and can access their required resources. Confirm all five Key Vault entries exist and are valid without printing their values. Stop if any prerequisite is missing or cannot be verified.
3. Install through the approved Flux workflow with `infra-production`; there is no separate Authentik Kustomization. If a manual bootstrap is explicitly approved and Flux does not yet manage these resources, apply the chart source in `flux-system` before the overlay:
   ```bash
   kubectl apply -f kubernetes/infra/helm/authentik.yaml
   kubectl apply -k kubernetes/infra/authentik/overlays/default
   ```
4. Confirm the ExternalSecrets are Ready, `authentik-db` is initialized and healthy, and the Authentik server and worker pods are Ready. Stop and diagnose any failure; do not rerun bootstrap to fix it.
   ```bash
   kubectl get externalsecrets.external-secrets.io,clusters.postgresql.cnpg.io,pods -n authentik
   ```
5. From a trusted workstation, start a loopback-only port-forward:
   ```bash
   kubectl port-forward --address 127.0.0.1 -n authentik svc/authentik-server 9000:80
   ```
   Open `http://127.0.0.1:9000/if/flow/initial-setup/` with the trailing slash. Have the operator create the bootstrap administrator and verify sign-in and recovery. Keep the port-forward on `127.0.0.1`; stop it with Ctrl-C when done.
6. Verify a CNPG Backup is `completed` and its base-backup files exist before relying on the installation. See [Verify an Authentik backup](#verify-an-authentik-backup). If setup or backup verification fails, stop before onboarding apps. Do not delete or reinitialize the database.

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
2. After the phase is `completed`, use the approved read-only Azure identity to list base-backup files:
   ```bash
   az storage blob list --auth-mode login --account-name lhshomelabbackup \
     --container-name authentik --prefix authentik-db-backup/base/ \
     --query '[].name' -o tsv
   ```
   Confirm the backup directory contains both `backup.info` and `data.tar.gz`. A ScheduledBackup object alone does not prove a backup exists. If you cannot confirm the phase or files, stop and resolve the backup or inventory access problem.

## Authentik LAN Ingress and TLS

Use the Authentik chart Ingress for LAN access at `https://authentik.homelab.leehosanganson.dev` through the private Traefik load balancer (`192.168.1.250`). The desired Ingress uses class `traefik`, TLS secret `authentik-tls`, and the existing `letsencrypt-cloudflare` DNS-01 ClusterIssuer. The issuer may create temporary challenge records. Do not manually create permanent DNS records or create or modify Cloudflare Tunnel routes.

1. Confirm the target context and use a LAN client for the DNS and HTTPS checks. Inspect the GitOps and Ingress resources without changing them:
   ```bash
   kubectl get kustomizations.kustomize.toolkit.fluxcd.io infra-production -n flux-system
   kubectl get helmreleases.helm.toolkit.fluxcd.io -n authentik
   kubectl get ingress -n authentik
   kubectl describe ingress -n authentik
   kubectl get certificates.cert-manager.io authentik-tls -n authentik
   ```
2. Confirm `infra-production`, the Authentik HelmRelease, and the certificate report Ready. Check that the Ingress matches the host, class, TLS secret, and issuer above.
3. From the LAN, confirm the hostname resolves to the private load balancer and the regular sign-in page loads over HTTPS with a trusted certificate for that hostname. Do not bypass certificate validation or rerun initial setup. These checks verify the LAN path only.
4. If any check fails, stop and diagnose the LAN path. Use the loopback-only fallback for administrator access rather than changing DNS or Tunnel routing.

## Manage users, groups, and application bindings

1. Complete the [existing-installation preflight](#preflight-for-an-existing-installation). Configure only approved Google or GitHub login sources, and leave enrollment disabled or invitation-only.
2. Verify the owner's identity in the Authentik admin UI before adding it to `homelab-allowlist`. The login source identifies the user; the application binding decides who gets access.
3. **An Authentik Application with no bindings allows access by default.** Before exposing the app, bind it to `homelab-allowlist` or a narrower approved group. Check that no other binding grants access outside the approved group.
4. Test with both an approved identity and a signed-in nonmember. If the nonmember can access the app or the result is unclear, keep it unavailable until the binding is fixed. Do not remove the only binding from a live app as a rollback.

## Onboard Mini QR with ForwardAuth

### Prerequisites

1. Complete the [existing-installation preflight](#preflight-for-an-existing-installation) and verify [LAN Ingress and TLS](#authentik-lan-ingress-and-tls). Have an allowlisted identity and a nonmember available for testing.
2. In the Authentik admin UI, create or verify a Proxy Provider in **Forward auth (single application)** mode. Set the external host to `https://qr.homelab.leehosanganson.dev`.
3. Link the provider to the Mini QR Application and assign it to the Authentik embedded outpost. Bind the Application to `homelab-allowlist` and confirm no other bindings grant access outside that group. Git does not manage the provider, Application, outpost assignment, or group binding. Do not proceed to deployment until the operator verifies all four.

### Reconcile and verify

1. After an authorized deployment, check both Flux Kustomizations:
   ```bash
   flux get kustomizations -n flux-system
   ```
   `apps-production` reconciles the Mini QR Ingress, ForwardAuth middleware, and NetworkPolicy. `infra-production` reconciles the `mini-qr-outpost` callback route. They reconcile independently; either can finish first. Keep Mini QR unavailable to normal users during reconciliation and testing. Wait for both to report Ready at the intended revision before acceptance testing.
2. Check that only the Mini QR Ingress uses its ForwardAuth middleware. On the existing Mini QR hostname, the HTTPS `/outpost.goauthentik.io/` path must route directly to Authentik without passing through ForwardAuth. The exact callback is `https://qr.homelab.leehosanganson.dev/outpost.goauthentik.io/callback`. Verify it reaches Authentik, uses the existing Mini QR Ingress certificate (`mini-qr-tls`), and completes in the browser without a redirect loop.
3. In separate clean browser sessions, confirm a signed-out user is redirected to sign-in, an allowlisted user can load Mini QR, and a signed-in nonmember is denied without receiving Mini QR content.
4. Confirm the Mini QR Service remains a ClusterIP. The NetworkPolicy is intended to allow only Traefik pods in `kube-system` to reach TCP port 8080. Verify Traefik still reaches the backend and an authorized test from a non-Traefik pod cannot connect to either the ClusterIP or a Mini QR Pod IP on that port. Confirm plain HTTP and any alternate route do not serve unauthenticated Mini QR content.

**Stop or roll back:** Flux readiness does not prove enforcement. The callback, access, and bypass checks remain required before accepting the service. If any check fails, keep the gate fail-closed (deny access without a successful login). If you cannot confirm denial, take Mini QR offline through the approved GitOps workflow and verify it no longer serves content. Do not remove the middleware from a live Ingress or restore unauthenticated access.

## Karakeep native OIDC (deferred)

Leave OIDC inactive and keep existing password and signup settings. Karakeep v0.35.0 requires both `OAUTH_WELLKNOWN_URL` and `OAUTH_CLIENT_ID` to enable its OAuth provider. Do not add the client ID or credential references until a separate Karakeep review approves activation. Do not change Authentik Ingress or Tunnel routes as part of activation.

Use these steps to plan the separate review and carry out activation only after approval:

1. Complete the [existing-installation preflight](#preflight-for-an-existing-installation). Confirm `https://karakeep.leehosanganson.dev` is the intended public URL and verify the existing routing without changing it.
2. Create the Authentik OIDC Application and provider with the exact strict redirect URI `https://karakeep.leehosanganson.dev/api/auth/callback/custom`. Bind the Application to `homelab-allowlist` or a narrower approved group. Verify the binding with allowed and denied identities before enabling OIDC in Karakeep.
3. Verify that `https://authentik.homelab.leehosanganson.dev/application/o/karakeep/.well-known/openid-configuration` returns valid OpenID metadata. Confirm the Karakeep server can reach discovery and the advertised JWKS and token endpoints, and a user's browser can reach the authorization endpoint and return to the callback. If Cloudflare Access or another layer blocks a required request, stop. Any supported access path needs its own review.
4. Once the provider exists, store its client ID and secret in Azure Key Vault. Verify the entries exist before adding `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET` via the `karakeep-secrets-external` ExternalSecret; missing entries can disrupt `karakeep-secrets`. Verify the ExternalSecret reports Ready. Never store credentials in `values.yaml` or a ConfigMap.
5. Set `NEXTAUTH_URL=https://karakeep.leehosanganson.dev` and `OAUTH_WELLKNOWN_URL` to the verified discovery URL. Optionally set `OAUTH_PROVIDER_NAME=Authentik`. Keep `OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING=false` and leave `DISABLE_PASSWORD_AUTH` and `DISABLE_SIGNUPS` unchanged. `DISABLE_SIGNUPS` also disables OAuth signup.
6. Verify email verification and linking for an existing account, owner/admin mapping, and recovery before switching login methods. On an empty instance, the first account becomes administrator. Test login, logout, denied users, duplicate or existing accounts, password and signup behavior, callbacks, sessions, and API/mobile/browser clients. Do not assume removing an Authentik group membership revokes an active Karakeep session.

**Stop or roll back:** Keep local login until a tested transition prevents unauthorized local-password access without locking out the owner. If activation fails, revert only the Karakeep OIDC settings and restore the last known working app-local authentication settings. Keep any outer access gate in place. Preserve the Authentik provider and user data until app sessions and account mappings have been reviewed.

## CNPG recovery and infrastructure rollback

Do not remove Authentik from `infra-production` without a reviewed plan: Flux prunes resources removed from its inventory. Preserve the database, PVCs, backups, Key Vault values, and long-lived `AUTHENTIK_SECRET_KEY` during rollback.

CNPG `bootstrap.recovery` creates a **new Cluster**; changing `initdb` to `recovery` on an initialized Cluster does not restore it. Follow the read-only checks in [Cluster Recovery: CNPG Database Recovery](cluster-recovery.md#phase-4--cnpg-database-recovery), then stop until a replacement-cluster and cutover plan is approved. Do not create, delete, or replace a Cluster, PVC, or data without that plan.

## References

- [Authentik Kubernetes installation](https://docs.goauthentik.io/install-config/install/kubernetes/) — chart installation and production database guidance.
- [Authentik first steps](https://docs.goauthentik.io/install-config/first-steps/) — initial admin, application/provider setup, and group-binding guidance.
- [Authentik OAuth2/OIDC provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/) — native OIDC provider configuration.
- [Authentik policy bindings](https://docs.goauthentik.io/customize/policies/bindings/) — application bindings and policy evaluation.
- [Karakeep configuration](https://docs.karakeep.com/configuration/environment-variables) — OAuth, signup, password, and linking settings.
- [Karakeep v0.35.0 auth implementation](https://github.com/karakeep-app/karakeep/blob/v0.35.0/apps/web/server/auth.ts) — version-specific signup, account linking, first-user role, and session behavior.
