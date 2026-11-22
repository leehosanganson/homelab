# Homelab SSO: Authentik and Karakeep Pilot

This runbook describes the staged setup for Authentik as the homelab identity provider and Karakeep as the first native OIDC integration. It does **not** authorize deployment or change production access. The initial PR prepares the Authentik manifests and a dedicated suspended Flux Kustomization; it does not deploy Authentik, either automatically or at this time. Configuring providers and activating Karakeep SSO require the external secrets and account checks below.

## Access model

Use an Authentik group named `homelab-allowlist` as the easy-to-manage membership list. Add the owner and each approved user to that group in Authentik. Bind each integrated Authentik Application to that group (or to a narrower service-specific group when roles differ). Removing a user from the group blocks future app authorizations, but an application's existing session may need separate revocation.

Do not allow every Google or GitHub login merely because it is a desired sign-in option. A provider authenticates an identity; the group binding authorizes access. Authentik's application policy behavior is fail-open when no binding is configured, so verify the binding exists and uses the intended policy-engine mode before connecting an application. Leave open enrollment disabled or invitation-only unless there is a specific need.

## Before enabling Authentik

The Kubernetes manifests refer to values in Azure Key Vault. Create these values through the existing secure Key Vault workflow; never commit them or send them in chat.

| Azure Key Vault entry | Kubernetes secret/key | Purpose |
|---|---|---|
| `authentik-secret-key` | `authentik-env` / `AUTHENTIK_SECRET_KEY` | Long-lived Authentik signing/encryption key. Generate securely and preserve across upgrades/restores; do not rotate casually. |
| `authentik-db-username` | `authentik-db-env` / `username` | CNPG initial database owner; value must be `authentik`. |
| `authentik-db-password` | `authentik-db-env` / `password` | CNPG/Authentik database password. |
| `homelab-backup-storageaccount-name` | `authentik-backup-env` / `storage-account-name` | Existing shared backup storage account reference. |
| `authentik-blob-sas` | `authentik-backup-env` / `blob-sas` | SAS token scoped to the Authentik backup destination. |

The Key Vault keys must exist before Authentik is first created. The chart's bundled PostgreSQL is disabled; this service uses its separate CNPG database.

## First deployment gate

This procedure is for a **fresh first deployment only**. Before creating anything:

1. Verify that all five Key Vault secret names in the table above exist in `lhs-kubernetes-keyvault`. List names only; do not print or copy secret values:
   ```bash
   az keyvault secret list --vault-name lhs-kubernetes-keyvault \
     --query "[?name=='authentik-secret-key' || name=='authentik-db-username' || name=='authentik-db-password' || name=='homelab-backup-storageaccount-name' || name=='authentik-blob-sas'].name" \
     -o tsv
   ```
   Confirm every required name is present. Resolve missing values through the approved Key Vault workflow before proceeding.
2. Check for existing Authentik clusters, persistent volume claims, or data/backups that may need restoration. For example, inspect the current cluster and read-only Barman inventory:
   ```bash
   kubectl get clusters.postgresql.cnpg.io,pvc -A
   az storage blob list --auth-mode login --account-name lhshomelabbackup --container-name authentik --prefix authentik-db-backup/base/ --num-results 1 --query 'length(@)' -o tsv
   ```
   If any Authentik data already exists, a backup is present from a prior deployment, or the data state is uncertain, **stop**. Do not use this fresh-install procedure; follow the [Cluster Recovery Phase 4 stop boundary](cluster-recovery.md#phase-4--cnpg-database-recovery) and obtain a separate, explicit recovery plan. Also stop if Authentik resources are already managed by the old `infra-production` configuration: removing them from a pruning Kustomization can delete them, so the ownership transition needs its own reviewed plan.
3. Confirm that the infrastructure prerequisites are ready: External Secrets Operator can read the Azure Key Vault store, and the CNPG operator and required CRDs are healthy. Confirm the intended cluster context, then verify the production root Kustomization (`flux-system`) is Ready and has reconciled the child Kustomization:
   ```bash
   flux get kustomizations flux-system
   flux get kustomizations authentik-production
   kubectl get kustomization authentik-production -n flux-system -o jsonpath='{.spec.suspend}'
   ```
   Do not continue unless the root is Ready and the child reports `suspend=true`. Then manually create the initial resources from the overlay:
   ```bash
   kubectl apply -k kubernetes/infra/authentik/overlays/default
   ```
   This command is an operator step for the first deployment; it is **not run as part of this change**. It creates the Authentik namespace and resources, including ExternalSecrets, the HelmRelease, CNPG Cluster, ObjectStore, and scheduled backup. The `authentik-production` Flux Kustomization is suspended, and `infra-production` excludes the Authentik workload overlay (the shared HelmRepository source may remain); neither Flux Kustomization creates the Authentik workload or database at this stage.
4. Wait for the ExternalSecrets, CNPG database, Authentik server, and worker to become healthy. Check their status and pod readiness:
   ```bash
   kubectl get externalsecrets.external-secrets.io,clusters.postgresql.cnpg.io,pods -n authentik
   ```
   Keep the Ingress disabled. Verify that CNPG has completed a successful full base backup before handing the resources to Flux. For example, inspect the backup list read-only from the healthy CNPG instance:
   ```bash
   kubectl exec -n authentik authentik-db-1 -- barman-cloud-backup-list --format json lhshomelabbackup/authentik authentik-db-backup
   ```
   Confirm that the output contains a successful full base backup. Do not proceed if the backup is absent or failed.
5. Only after verifying that backup, make a reviewed Git change setting `spec.suspend: false` on `authentik-production` in `fluxcd/clusters/production/authentik.yaml`. The production root Kustomization reconciles this child Kustomization resource, so the Git change durably updates its suspend state; the child then adopts the exact resources already created from the same overlay. Do **not** use `flux resume kustomization authentik-production` alone: the root Kustomization would restore the Git value `suspend: true` on its next reconciliation.

This is not a DNS or Ingress activation procedure. Do not create DNS, enable the Authentik Ingress, or expose Authentik as part of first deployment; keep Ingress disabled.

## Initial Authentik setup

1. Confirm your `kubectl` context is the intended cluster and that the Authentik server Service is ready: `kubectl get pods,svc -n authentik`. Check that no Cloudflare Tunnel or other external route points directly to the Authentik Service. Keep this operator-controlled setup session on a trusted workstation.
2. Start a loopback-only port-forward to the Authentik server Service:
   ```bash
   kubectl port-forward --address 127.0.0.1 -n authentik svc/authentik-server 9000:80
   ```
   Leave this command running. It binds only to the local machine; do not replace `127.0.0.1` with `0.0.0.0` or expose the forwarded port through another proxy.
3. On that same workstation, open `http://127.0.0.1:9000/if/flow/initial-setup/` (retain the trailing slash) and create a strong local bootstrap administrator account. Do not protect this initial setup/admin path with Authentik itself.
4. While the port-forward is running, confirm the local bootstrap administrator can sign in and recover access. Store recovery credentials safely outside Git.
5. Stop the port-forward with Ctrl-C when setup and sign-in checks are complete. Do not use a public hostname for initial setup while the Ingress is disabled.
6. For later Authentik admin tasks below, reuse the same loopback-only port-forward procedure while working in the admin UI, then stop it with Ctrl-C when finished. Create the `homelab-allowlist` group. Keep the bootstrap administrator account separate from public social-login accounts. Do not add any social source until the local admin and backup/recovery path work.
7. Configure GitHub OAuth and Google OAuth sources using their respective official provider setup guides. Store their client secrets in Authentik's protected configuration, not in Kubernetes YAML or this repository. Use only the requested providers.
8. Configure source/enrollment flows so users cannot obtain application access merely by choosing a provider. Add the owner's social identity to `homelab-allowlist` only after verifying it in the Authentik admin UI. Add future approved identities to this group; do not enable a broad enrollment shortcut as the allowlist.
9. For each app, configure an Authentik Application and the matching provider. Add a group binding to the Authentik Application for `homelab-allowlist` before distributing the login URL or allowing traffic to the app. Verify an unapproved account is denied. Authentik docs note that no bindings means access is granted; do not leave an application unbound unintentionally.

## Karakeep native OIDC pilot (deferred activation)

This change does not activate Karakeep OIDC or create DNS/Ingress for Authentik. Karakeep v0.35.0 enables its OAuth provider only when both `OAUTH_WELLKNOWN_URL` and `OAUTH_CLIENT_ID` are configured; its current configuration leaves the provider inactive and does not change password/signup policy. The client credentials cannot be created until Authentik is available and its Karakeep provider has been configured. A later app-specific change must add the Azure Key Vault references after those values exist. Before any separately reviewed OIDC activation, verify that the exact provider discovery URL returns valid OpenID metadata, the Karakeep server can reach the discovery document and advertised JWKS/token endpoints, and a user's browser can reach the advertised authorization endpoint and return to Karakeep's callback. Do not activate OIDC if Cloudflare Access or another protection layer blocks required server-to-server requests; a narrowly scoped supported access path requires its own design and review. Keep the Authentik Ingress disabled until that separate change is approved.

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

### Before PR merge

- [ ] Production root includes `authentik-production` with `spec.suspend: true`, and `infra-production` does not include the Authentik overlay.
- [ ] No secret values appear in the Git diff.
- [ ] `kustomize build kubernetes/infra/authentik/overlays/default` succeeds.
- [ ] `kustomize build kubernetes/infra/overlays/production` succeeds.
- [ ] Helm chart version/value render uses external PostgreSQL, does not enable chart-bundled PostgreSQL, and contains no Ingress by default.
- [ ] Rendered server and worker run non-root, disable privilege escalation, and drop all Linux capabilities.
- [ ] CNPG database and Barman backup resources use Authentik-specific names and the intended Key Vault backup references.

### Before manual first apply

- [ ] All five required Key Vault keys above exist in `lhs-kubernetes-keyvault` and are scoped correctly.
- [ ] External Secrets Operator can read the Azure Key Vault store, and the CNPG operator and required CRDs are healthy.
- [ ] No existing Authentik data or backups need recovery; stop and use a separately reviewed recovery plan if any data exists or its state is uncertain.

### After the fresh first deployment and Git adoption

- [ ] Authentik server, worker, database, backup, and ExternalSecrets report healthy/Ready, and a successful full base backup was verified before the reviewed Git change unsuspended `authentik-production`.
- [ ] The root-managed `authentik-production` Kustomization is unsuspended in Git; do not use `flux resume` alone as a durable change. No DNS or Ingress was created or enabled.
- [ ] A TLS certificate is not expected while the Ingress remains disabled.
- [ ] Local bootstrap administrator sign-in and recovery are verified before connecting any app.
- [ ] Google and GitHub source logins work only as configured; a non-allowlisted user cannot access a bound application.
- [ ] Karakeep's non-secret public URL and Authentik discovery URL are prepared; before OIDC activation, verify discovery metadata and all required endpoint reachability as described above. No OAuth client ID/secret is referenced until those Key Vault values exist.
- [ ] After the follow-up OIDC activation, existing local Karakeep credentials or a documented recovery path still work until OIDC-only activation is explicitly approved; then verify the allowed/denied identity policy separately.

## Rollback

For the Authentik foundation, revert the PR through the repository workflow and preserve the CNPG data, backup objects, and Azure Key Vault values unless a separate data-removal decision is made. Do not delete the identity database as part of an application rollback. CNPG restore uses `bootstrap.recovery` to create a **new Cluster**; it does not restore an initialized Cluster in place. Never change the initialized Authentik Cluster's `bootstrap.initdb` to `bootstrap.recovery` as a restore. The inventory in [Cluster Recovery — Phase 4](cluster-recovery.md#phase-4--cnpg-database-recovery) identifies Authentik's existing manifest at `kubernetes/infra/authentik/base/db/cluster.yaml`, but that file is not a ready-to-apply recovery manifest. Verify the Authentik backup in `lhshomelabbackup/authentik` under the `authentik-db-backup` server prefix as a read-only pre-check. Phase 4 is not yet a complete executable Authentik restore/cutover procedure: this repository has no validated replacement-cluster name/service/cutover runbook. Stop before creating, deleting, or replacing any Cluster or data until an explicit recovery plan covers a separate recovery Cluster, unique WAL archive `serverName`, data verification, application service/host cutover, and preservation or planned retirement of the original data. Preserve the long-lived `AUTHENTIK_SECRET_KEY`; changing it can invalidate sessions/tokens and disrupt identity integrations.

For Karakeep, revert only the application-specific OIDC configuration and restore the last known working app-local auth settings. Do not remove the Authentik provider or user data until all app sessions and account mappings have been reviewed. If the app is protected by an outer proxy gate in a later phase, roll back the gate only to a still-protected state; do not inadvertently publish a private service.

## References

- [Authentik Kubernetes installation](https://docs.goauthentik.io/install-config/install/kubernetes/) — chart installation and production database guidance.
- [Authentik first steps](https://docs.goauthentik.io/install-config/first-steps/) — initial admin, application/provider setup, and group-binding guidance.
- [Authentik OAuth2/OIDC provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/) — native OIDC provider configuration.
- [Authentik policy bindings](https://docs.goauthentik.io/customize/policies/bindings/) — application bindings and policy evaluation.
- [Karakeep configuration](https://docs.karakeep.com/configuration/environment-variables) — OAuth, signup, password, and linking settings.
- [Karakeep v0.35.0 auth implementation](https://github.com/karakeep-app/karakeep/blob/v0.35.0/apps/web/server/auth.ts) — version-specific signup, account linking, first-user role, and session behavior.
