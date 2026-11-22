# Homelab SSO: Authentik and Karakeep Pilot

This runbook covers a staged Authentik installation and a later Karakeep OpenID Connect (OIDC) pilot. The first stage installs Authentik and verifies its database, application health, and backup before the PR is merged. The PR then makes the normal `infra-production` Flux reconciliation manage the same resources. This stage does **not** enable DNS, Ingress, or OIDC for Karakeep or another application.

## Required Azure Key Vault values

The Kubernetes manifests refer to these values in Azure Key Vault. They must exist before the manual first apply, but are not a prerequisite to merging the PR if no apply is being performed. Create values only through the approved secure Key Vault workflow; never commit them or send them in chat.

| Azure Key Vault entry | Kubernetes secret/key | Purpose |
|---|---|---|
| `authentik-secret-key` | `authentik-env` / `AUTHENTIK_SECRET_KEY` | Long-lived Authentik signing/encryption key. Generate securely and preserve across upgrades/restores; do not rotate casually. |
| `authentik-db-username` | `authentik-db-env` / `username` | CNPG initial database owner; value must be `authentik`. |
| `authentik-db-password` | `authentik-db-env` / `password` | CNPG/Authentik database password. |
| `homelab-backup-storageaccount-name` | `authentik-backup-env` / `storage-account-name` | Existing shared backup storage account reference. |
| `authentik-blob-sas` | `authentik-backup-env` / `blob-sas` | SAS token scoped to the Authentik backup destination. |

The chart's bundled PostgreSQL is disabled; Authentik uses a separate CloudNativePG (CNPG) database.

## Fresh first installation — before PR merge

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
4. Start a loopback-only port-forward to the Authentik server Service:
   ```bash
   kubectl port-forward --address 127.0.0.1 -n authentik svc/authentik-server 9000:80
   ```
   On the same trusted workstation, open `http://127.0.0.1:9000/if/flow/initial-setup/` (retain the trailing slash), complete the local bootstrap administrator setup, and verify that the server responds and the administrator can sign in. Keep the port-forward bound to `127.0.0.1`; do not expose it through a public route. Stop it with Ctrl-C after the check.
5. Verify that a successful full Barman base backup exists before merging. From the healthy CNPG instance, inspect the backup list:
   ```bash
   kubectl exec -n authentik authentik-db-1 -- \
     barman-cloud-backup-list --format json \
     lhshomelabbackup/authentik authentik-db-backup
   ```
   Confirm the output shows a completed successful full base backup, not only a WAL archive or a scheduled-backup object. Wait for the scheduled backup if needed. If no successful base backup is visible, stop and do not merge the PR.
6. Only after the database, server, worker, local port-forward check, and full backup are verified, merge the PR through its normal review process. The PR adds the Authentik overlay to `infra-production`; after merge, Flux reconciles and manages the already-applied resources through that existing Kustomization. There is no separate Authentik Kustomization or Git adoption step.

Do not create DNS records, enable or expose the Authentik Ingress, or activate OIDC for any application during this stage. Keep Ingress disabled.

## Later Authentik configuration

After the first-install checks and a separate decision to configure identity providers, use a loopback-only port-forward as above. Verify bootstrap administrator sign-in and recovery, and store recovery credentials safely outside Git. Then create the `homelab-allowlist` group. Keep the bootstrap administrator separate from social-login accounts and leave open enrollment disabled or invitation-only.

Configure only approved Google or GitHub sources. A provider authenticates an identity; a group binding authorizes access. Add the owner's verified identity to `homelab-allowlist` only after confirming it in the admin UI. Authentik grants access to an Application when no binding is configured, so bind each Application to `homelab-allowlist` or a narrower service-specific group before allowing access. Test both an approved and a non-allowlisted identity. These steps are separate from the initial install and do not authorize DNS, Ingress, or application OIDC activation.


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

- [ ] Required Authentik Key Vault values exist before the manual apply; no secret values appear in Git.
- [ ] `kustomize build kubernetes/infra/authentik/overlays/default` and `kustomize build kubernetes/infra/overlays/production` succeed.
- [ ] The chart uses external PostgreSQL, does not enable bundled PostgreSQL, and leaves Ingress disabled.
- [ ] Rendered server and worker run non-root, disable privilege escalation, and drop all Linux capabilities.
- [ ] The fresh `authentik-db` Cluster is initialized and healthy; Authentik server and worker are Ready.
- [ ] The loopback-only port-forward reaches the local initial-setup page and bootstrap administrator sign-in succeeds.
- [ ] A completed, successful full Barman base backup is visible for `authentik-db-backup`.
- [ ] No DNS or Ingress was created or enabled, and no application OIDC integration was activated.

### After PR merge

- [ ] `infra-production` is Ready and manages the Authentik resources already created from the same overlay; there is no separate Authentik Kustomization or adoption step.
- [ ] Ingress remains disabled. No DNS or application OIDC configuration was activated.
- [ ] A TLS certificate is not expected while Ingress remains disabled.
- [ ] Later provider setup and application integrations follow a separate review and verify the intended allowlist policy.

## Rollback

Do not revert this PR or remove Authentik from `infra-production` blindly: the Flux Kustomization prunes resources that disappear from its inventory. Any rollback must have a reviewed plan that preserves the CNPG data, backup objects, and Azure Key Vault values unless a separate data-removal decision is made. Do not delete the identity database as part of an application rollback. CNPG restore uses `bootstrap.recovery` to create a **new Cluster**; it does not restore an initialized Cluster in place. Never change the initialized Authentik Cluster's `bootstrap.initdb` to `bootstrap.recovery` as a restore. The inventory in [Cluster Recovery — Phase 4](cluster-recovery.md#phase-4--cnpg-database-recovery) identifies Authentik's existing manifest at `kubernetes/infra/authentik/base/db/cluster.yaml`, but that file is not a ready-to-apply recovery manifest. Verify the Authentik backup in `lhshomelabbackup/authentik` under the `authentik-db-backup` server prefix as a read-only pre-check. Phase 4 is not yet a complete executable Authentik restore/cutover procedure: this repository has no validated replacement-cluster name/service/cutover runbook. Stop before creating, deleting, or replacing any Cluster or data until an explicit recovery plan covers a separate recovery Cluster, unique WAL archive `serverName`, data verification, application service/host cutover, and preservation or planned retirement of the original data. Preserve the long-lived `AUTHENTIK_SECRET_KEY`; changing it can invalidate sessions/tokens and disrupt identity integrations.

For Karakeep, revert only the application-specific OIDC configuration and restore the last known working app-local auth settings. Do not remove the Authentik provider or user data until all app sessions and account mappings have been reviewed. If the app is protected by an outer proxy gate in a later phase, roll back the gate only to a still-protected state; do not inadvertently publish a private service.

## References

- [Authentik Kubernetes installation](https://docs.goauthentik.io/install-config/install/kubernetes/) — chart installation and production database guidance.
- [Authentik first steps](https://docs.goauthentik.io/install-config/first-steps/) — initial admin, application/provider setup, and group-binding guidance.
- [Authentik OAuth2/OIDC provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/) — native OIDC provider configuration.
- [Authentik policy bindings](https://docs.goauthentik.io/customize/policies/bindings/) — application bindings and policy evaluation.
- [Karakeep configuration](https://docs.karakeep.com/configuration/environment-variables) — OAuth, signup, password, and linking settings.
- [Karakeep v0.35.0 auth implementation](https://github.com/karakeep-app/karakeep/blob/v0.35.0/apps/web/server/auth.ts) — version-specific signup, account linking, first-user role, and session behavior.
