# Homelab SSO: Authentik, Mini QR, and Karakeep

This runbook covers Authentik, the Mini QR ForwardAuth pilot, and a deferred Karakeep OpenID Connect (OIDC) pilot. Foundation PR #1235 is merged, and Flux manages Authentik. Its database, workloads, and backup were verified. The operator has verified Authentik administrator sign-in and recovery. The Mini QR pilot does not change the Authentik chart Ingress. The Ingress is intended for LAN access at `https://authentik.homelab.leehosanganson.dev`, through the private Traefik load balancer (`192.168.1.250`), using the existing `letsencrypt-cloudflare` DNS-01 issuer. The issuer may create temporary challenge records. Do not manually create permanent DNS records or Cloudflare Tunnel routes. The external Tunnel route has not been verified, so do not claim that public access is blocked. Karakeep OIDC and other application authentication remain unchanged.

## Required Azure Key Vault values

The Kubernetes manifests refer to these values in Azure Key Vault. These values were required for the historical manual first apply described below. They are not instructions to repeat that apply or create new secret data for the current Ingress follow-up. Create or update values only through the approved secure Key Vault workflow; never commit them or send them in chat.

| Azure Key Vault entry | Kubernetes secret/key | Purpose |
|---|---|---|
| `authentik-secret-key` | `authentik-env` / `AUTHENTIK_SECRET_KEY` | Long-lived Authentik signing/encryption key. Generate securely and preserve across upgrades/restores; do not rotate casually. |
| `authentik-db-username` | `authentik-db-env` / `username` | CNPG initial database owner; value must be `authentik`. |
| `authentik-db-password` | `authentik-db-env` / `password` | CNPG/Authentik database password. |
| `homelab-backup-storageaccount-name` | `authentik-backup-env` / `storage-account-name` | Existing shared backup storage account reference. |
| `authentik-blob-sas` | `authentik-backup-env` / `blob-sas` | Container-scoped SAS token for the `authentik` container. It is HTTPS-only, has `racwdl` permissions, and expires 180 days after issue. |

Renew `authentik-blob-sas` before it expires; start the renewal well ahead of the expiry date (for example, 30 days). Create a replacement SAS for only the `authentik` container, with HTTPS-only access and the required `racwdl` permissions, then update the Key Vault secret through the approved secure workflow. Never paste, print, log, or commit the token. Allow the ExternalSecret to refresh and confirm it is Ready before relying on the replacement. Do not wait for expiry: an expired token stops database backups.

The chart's bundled PostgreSQL is disabled; Authentik uses a separate CloudNativePG (CNPG) database.

## Historical one-time fresh-install procedure — pre-merge

**Do not repeat this procedure for the current deployment.** It records the one-time fresh-install steps used before foundation PR #1235 was merged. The database, workloads, and backup have already been verified, and Flux now manages Authentik. The procedure is retained for historical reference and for a genuinely separate fresh installation only.

At the time of this procedure, Authentik Ingress was off. Use the loopback-only port-forward below for initial setup; do not use the LAN Ingress URL in this historical sequence.

This sequence is only for a confirmed fresh installation with no Authentik database data to recover. Before apply, inspect for an existing Authentik Cluster or persistent volume claim and check the approved read-only backup inventory. If any prior Authentik database, PVC, or backup exists, or the data state is uncertain, stop and follow the [Cluster Recovery Phase 4 stop boundary](cluster-recovery.md#phase-4--cnpg-database-recovery). Do not apply the fresh-install overlay in that case.

1. Check the intended Kubernetes context and confirm the CNPG operator and External Secrets Operator (ESO) are healthy and can access the required resources. Confirm that all five Key Vault values in the table above exist and are valid. Do not print secret values. If any value is missing, or its status cannot be confirmed, stop before applying; resolve it through the approved Key Vault workflow.
   ```bash
   kubectl get clusters.postgresql.cnpg.io,pvc -A
   ```
2. From the PR branch, and only after confirming this is a fresh installation, apply the Authentik chart source and overlay before merging the PR:
   ```bash
   kubectl apply -f kubernetes/infra/helm/authentik.yaml
   kubectl apply -k kubernetes/infra/authentik/overlays/default
   ```
   The first command creates the HelmRepository in `flux-system`, which the HelmRelease needs to fetch the chart. The second creates the namespace, ExternalSecrets, HelmRelease, CNPG Cluster using `initdb`, ObjectStore, and scheduled backup. Do not run this command when restoring an existing installation.
3. Wait for the ExternalSecrets to become Ready, the `authentik-db` Cluster to report healthy, and the Authentik server and worker pods to be Ready:
   ```bash
   kubectl get externalsecrets.external-secrets.io,clusters.postgresql.cnpg.io,pods -n authentik
   kubectl get pods -n authentik -w
   ```
   Confirm that the `authentik-db` cluster is initialized and healthy before proceeding. If the database or either application workload is not healthy, stop and diagnose it; do not merge yet.
4. Start a loopback-only port-forward on a trusted workstation:
   ```bash
   kubectl port-forward --address 127.0.0.1 -n authentik svc/authentik-server 9000:80
   ```
   Open `http://127.0.0.1:9000/if/flow/initial-setup/` (retain the trailing slash) to complete initial setup. Keep the port-forward bound to `127.0.0.1`; do not expose it through a public route. Stop it with Ctrl-C after the check. Creating the bootstrap administrator is operator-controlled; report setup or sign-in as complete only after the operator performs and verifies it.
5. Verify the database backup before merging. The `authentik-backup-schedule` ScheduledBackup is set for 03:00 UTC daily, but it has not produced an automatic backup yet. An on-demand CNPG Backup named `authentik-manual-initial-backup` completed successfully. Check the Backup resource phase:
   ```bash
   kubectl get backups.postgresql.cnpg.io -n authentik authentik-manual-initial-backup \
     -o jsonpath='{.status.phase}{"\n"}'
   ```
   Confirm the phase is `completed`. The Azure blob listing also confirmed `authentik-db-backup/base/20261122T215230/backup.info` and `authentik-db-backup/base/20261122T215230/data.tar.gz`.

   To verify blob names and count read-only, retrieve the SAS directly into a temporary environment variable. Do not enable shell tracing, print the variable, or paste it into a command or log. The subshell and exit trap limit the variable's lifetime; it is also explicitly unset after use:
   ```bash
   (
     set +x
     trap 'unset AZURE_STORAGE_SAS_TOKEN' EXIT
     AZURE_STORAGE_SAS_TOKEN="$(az keyvault secret show \
       --vault-name lhs-kubernetes-keyvault \
       --name authentik-blob-sas --query value -o tsv)" || exit 1
     export AZURE_STORAGE_SAS_TOKEN
     az storage blob list --auth-mode key --account-name lhshomelabbackup \
       --container-name authentik --prefix authentik-db-backup/base/ \
       --query '[].name' -o tsv || exit 1
     az storage blob list --auth-mode key --account-name lhshomelabbackup \
       --container-name authentik --prefix authentik-db-backup/base/ \
       --query 'length(@)' -o tsv || exit 1
     unset AZURE_STORAGE_SAS_TOKEN
   )
   ```
   Confirm the listing includes a `backup.info` and `data.tar.gz` in a base-backup directory and that the count is non-zero. A scheduled-backup object alone is not proof that a base backup exists.

   If an immediate backup is needed before the next scheduled run, first inspect existing Backup resources and do not create a duplicate:
   ```bash
   kubectl get backups.postgresql.cnpg.io -n authentik
   ```
   Only if `authentik-manual-initial-backup` does not already exist and an immediate backup is still needed, create the CNPG Backup resource matching the successful initial backup:
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
   Then wait for its phase to become `completed` and repeat the read-only blob check. If the Backup name already exists, do not apply it again; verify that resource and its backup instead.
6. Before foundation PR #1235 was merged, its changes went through review and Flux then managed the already-applied resources through the existing `infra-production` Kustomization. There is no separate Authentik Kustomization or Git adoption step. This historical merge step is complete for the current deployment.

## Authentik Ingress follow-up (historical)

Ingress PR #1238 is merged. The [historical checklist](#historical-authentik-ingress-follow-up-checks) records the rollout results, not Mini QR acceptance. Do not repeat initial administrator setup on the existing installation. Use the read-only commands below to inspect the current state if needed.

1. Inspect the `infra-production` Flux Kustomization and Authentik HelmRelease:
   ```bash
   kubectl get kustomizations.kustomize.toolkit.fluxcd.io infra-production -n flux-system
   kubectl get helmreleases.helm.toolkit.fluxcd.io -n authentik
   ```
2. Inspect the Authentik Ingress. Confirm its host is `authentik.homelab.leehosanganson.dev`, its class is Traefik, and its TLS configuration uses `authentik-tls` and the existing DNS-01 issuer:
   ```bash
   kubectl get ingress -n authentik
   kubectl describe ingress -n authentik
   ```
3. Inspect the `authentik-tls` certificate:
   ```bash
   kubectl get certificates.cert-manager.io -n authentik
   ```

During the rollout, a LAN client reached `https://authentik.homelab.leehosanganson.dev/if/flow/initial-setup/` over HTTPS. The operator later verified administrator sign-in and recovery.

## Later Authentik configuration

For approved Authentik changes, use the LAN URL above or the loopback-only port-forward as a fallback. Keep recovery credentials outside Git, keep the bootstrap administrator separate from social-login accounts, and leave open enrollment disabled or invitation-only.

Configure only approved Google or GitHub sources. A provider authenticates an identity; a group binding authorizes access. Add the owner's verified identity to `homelab-allowlist` only after confirming it in the admin UI. Authentik grants access to an Application when no binding is configured, so bind each Application to `homelab-allowlist` or a narrower service-specific group before allowing access. Test both an approved and a non-allowlisted identity. These steps are separate from the initial install and do not authorize permanent DNS changes, Cloudflare Tunnel route changes, or application OIDC activation.


## Mini QR ForwardAuth pilot

**Required before merge:** An Authentik operator must create or verify a Proxy Provider in **Forward auth (single application)** mode with external host `https://qr.homelab.leehosanganson.dev`, link it to the Mini QR Application, and assign it to the Authentik embedded outpost. Confirm the Application is bound to `homelab-allowlist` and has no other bindings that grant access outside that group. Do not merge until the operator confirms this setup. Git does not manage the provider, application, outpost assignment, or group binding.

Only the Mini QR Ingress uses the ForwardAuth middleware. The HTTPS route for `/outpost.goauthentik.io/` sends requests directly to Authentik so the callback does not pass through ForwardAuth again. The existing Mini QR Ingress still supplies the certificate. The Mini QR Service remains a ClusterIP; the NetworkPolicy is intended to admit only `kube-system` Traefik pods to TCP port 8080.

**After merge:** `apps-production` reconciles the Mini QR Ingress and middleware independently of `infra-production`, which reconciles the callback route. Wait until both report Ready for the merged revision, then confirm the HTTPS callback route reaches Authentik before using protected Mini QR. If login fails, keep the gate fail-closed (deny access without a successful login) or take Mini QR offline. Do not restore unauthenticated public access.

**Pending after an authorized deployment:**

- Confirm the outpost path reaches Authentik over HTTPS with the existing Mini QR certificate and that the browser callback completes without a redirect loop.
- In separate clean browser sessions, verify that a signed-out request is sent to sign-in, an allowlisted identity can load Mini QR, and a signed-in nonmember is denied without receiving Mini QR content.
- Confirm Traefik can still reach the backend and a non-Traefik pod cannot reach it directly via either the ClusterIP or Pod IP. Verify that plain HTTP and any alternate route do not serve the app without authentication. Do not claim enforcement until these checks pass.

## Karakeep native OIDC pilot (deferred activation)

The Mini QR pilot does not activate Karakeep OIDC or change its authentication settings. The external Tunnel route remains unverified. Karakeep v0.35.0 enables its OAuth provider only when both `OAUTH_WELLKNOWN_URL` and `OAUTH_CLIENT_ID` are configured; its current configuration leaves the provider inactive and does not change password/signup policy. The client credentials cannot be created until Authentik is available and its Karakeep provider has been configured. A later app-specific change must add the Azure Key Vault references after those values exist. Before any separately reviewed OIDC activation, verify that the exact provider discovery URL returns valid OpenID metadata, the Karakeep server can reach the discovery document and advertised JWKS/token endpoints, and a user's browser can reach the advertised authorization endpoint and return to Karakeep's callback. Do not activate OIDC if Cloudflare Access or another protection layer blocks required server-to-server requests; a narrowly scoped supported access path requires its own design and review. Do not change the Authentik Ingress or Tunnel route as part of this Karakeep change.

When ready to activate:

1. Confirm the correct public URL is `https://karakeep.leehosanganson.dev`, that public DNS/Tunnel routing is intended, and that the callback URL can reach Authentik.
2. Create the Authentik OIDC application/provider for Karakeep with the exact strict redirect URI:
   `https://karakeep.leehosanganson.dev/api/auth/callback/custom`
3. Bind the Authentik Karakeep Application to `homelab-allowlist` (or a narrower approved group) and test allowed and denied identities before enabling OIDC in Karakeep.
4. Configure Karakeep v0.35.0 using its OIDC variables:
   - `NEXTAUTH_URL=https://karakeep.leehosanganson.dev`
   - `OAUTH_WELLKNOWN_URL` to the provider's Authentik OpenID configuration/discovery URL.
   - `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET` from the Authentik provider.
   - `OAUTH_PROVIDER_NAME=Authentik` (optional display name).
   - Keep `OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING=false`.
   - Keep `DISABLE_PASSWORD_AUTH` and `DISABLE_SIGNUPS` unchanged until existing users, owner/admin mapping, and recovery behavior are verified.
5. After Authentik is running and the Karakeep provider exists, store the client ID and secret using the repository's Azure Key Vault + ExternalSecret pattern (for example, `karakeep-authentik-client-id` and `karakeep-authentik-client-secret`). Add those required ExternalSecret references in a follow-up change only after the Key Vault entries have been created; adding missing refs to the existing `karakeep-secrets` ExternalSecret could make that Secret unavailable. Do not put credentials in `values.yaml` or a ConfigMap.
6. Verify a pre-existing Karakeep account's email verification and linking behavior before switching login methods. The first account created in an empty Karakeep instance receives the app's admin role, so verify which account would be first. Do not enable dangerous automatic email account linking just to bypass an account-migration issue.
7. Test login/logout, denied users, duplicate/existing accounts, account recovery, password-login and signup policy, API/mobile/browser clients, callbacks and sessions. Karakeep sessions are separate from Authentik sessions; removing an Authentik group membership does not by itself prove an existing Karakeep session has been revoked.

Karakeep's `DISABLE_SIGNUPS` setting disables signups generally, including OAuth signup. Do not toggle it based only on the desire to restrict enrollment. Similarly, preserve existing local login until a tested transition can prevent unauthorized local-password bypass without locking out the owner.

## Verification checklist

### Historical pre-merge fresh-install checks — foundation PR #1235 (already completed)

These checks document the one-time install and are not acceptance checks for the Mini QR pilot. Do not repeat the apply or setup sequence for the current deployment.

- [x] The `authentik-db` Cluster was initialized and healthy; Authentik server and worker were Ready.
- [x] The CNPG Backup completed, and the Azure blob listing showed base-backup contents (`backup.info` and `data.tar.gz`) for `authentik-db-backup`.
- Administrator setup was not completed during the foundation rollout; the operator later verified sign-in and recovery.

### Historical Authentik Ingress follow-up checks

- [x] Authentik Ingress PR #1238 merged.
- [x] `infra-production` reported Ready, and the Authentik HelmRelease reported Ready with `UpgradeSucceeded`.
- [x] The `authentik-tls` certificate reported Ready.
- [x] A LAN client reached the initial-setup flow over HTTPS.
- [x] The operator reported verifying Authentik administrator sign-in and recovery.

The Ingress is configured for `authentik.homelab.leehosanganson.dev` with class `traefik`, `authentik-tls`, and the existing DNS-01 issuer. Do not manually create permanent DNS records or Cloudflare Tunnel routes. The external Tunnel route remains unverified, and application OIDC activation is outside the scope of this rollout.

## Rollback

Do not revert the Authentik foundation PR or remove Authentik from `infra-production` blindly: the Flux Kustomization prunes resources that disappear from its inventory. Any rollback must have a reviewed plan that preserves the CNPG data, backup objects, and Azure Key Vault values unless a separate data-removal decision is made. Do not delete the identity database as part of an application rollback. CNPG restore uses `bootstrap.recovery` to create a **new Cluster**; it does not restore an initialized Cluster in place. Never change the initialized Authentik Cluster's `bootstrap.initdb` to `bootstrap.recovery` as a restore. The inventory in [Cluster Recovery — Phase 4](cluster-recovery.md#phase-4--cnpg-database-recovery) identifies Authentik's existing manifest at `kubernetes/infra/authentik/base/db/cluster.yaml`, but that file is not a ready-to-apply recovery manifest. Verify the Authentik backup in `lhshomelabbackup/authentik` under the `authentik-db-backup` server prefix as a read-only pre-check. Phase 4 is not yet a complete executable Authentik restore/cutover procedure: this repository has no validated replacement-cluster name/service/cutover runbook. Stop before creating, deleting, or replacing any Cluster or data until an explicit recovery plan covers a separate recovery Cluster, unique WAL archive `serverName`, data verification, application service/host cutover, and preservation or planned retirement of the original data. Preserve the long-lived `AUTHENTIK_SECRET_KEY`; changing it can invalidate sessions/tokens and disrupt identity integrations.

For Karakeep, revert only the application-specific OIDC configuration and restore the last known working app-local auth settings. Do not remove the Authentik provider or user data until all app sessions and account mappings have been reviewed. If the app is protected by an outer proxy gate in a later phase, roll back the gate only to a still-protected state; do not inadvertently publish a private service.

## References

- [Authentik Kubernetes installation](https://docs.goauthentik.io/install-config/install/kubernetes/) — chart installation and production database guidance.
- [Authentik first steps](https://docs.goauthentik.io/install-config/first-steps/) — initial admin, application/provider setup, and group-binding guidance.
- [Authentik OAuth2/OIDC provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/) — native OIDC provider configuration.
- [Authentik policy bindings](https://docs.goauthentik.io/customize/policies/bindings/) — application bindings and policy evaluation.
- [Karakeep configuration](https://docs.karakeep.com/configuration/environment-variables) — OAuth, signup, password, and linking settings.
- [Karakeep v0.35.0 auth implementation](https://github.com/karakeep-app/karakeep/blob/v0.35.0/apps/web/server/auth.ts) — version-specific signup, account linking, first-user role, and session behavior.
