# Authentik Service Onboarding Runbook

This runbook describes how to connect a Homelab service to the existing Authentik installation. It covers native OpenID Connect (OIDC) where the application supports it, and Authentik Forward auth for HTTP services that do not. It is an operating guide, not approval to change a service or the cluster. Onboard one service at a time through a reviewed GitOps change.

## Current Homelab state and safe preflight

The repository records Authentik as an installed, Flux-managed service in the `authentik` namespace, with a separate CloudNativePG database. The [Authentik SSO runbook](authentik-sso.md) records the foundation and Ingress checks and the operator report that initial administrator setup is complete. Sign-in and account recovery have not been independently verified. Verify both during preflight. These are repository records, not live health checks. Do not assume the current account or cluster state from this document alone.

The configured Authentik ingress is intended for LAN access at `https://authentik.homelab.leehosanganson.dev`, through the private Traefik load balancer. The external Cloudflare Tunnel route has not been verified. Do not claim that the hostname is inaccessible from outside the LAN, and do not create permanent DNS records or Tunnel routes as part of application onboarding. The DNS-01 certificate issuer can create temporary challenge records.

Before onboarding any service:

1. Read the [Authentik SSO runbook](authentik-sso.md), the relevant application configuration, and its current vendor authentication guide. Check current Flux, Authentik, database, and ingress health with read-only commands, for example:
   ```bash
   flux get kustomizations infra-production -n flux-system
   flux get helmreleases -n authentik
   kubectl get pods,svc,ingress -n authentik
   kubectl get clusters.postgresql.cnpg.io -n authentik
   ```
   Stop if Authentik or its database is unhealthy; do not troubleshoot by changing live resources.
2. From a trusted LAN client, visit the configured Authentik URL and verify sign-in with the existing administrator account. Confirm the administrator can reach the Admin interface. If the LAN Ingress is unavailable, use a loopback-only port-forward from a trusted workstation, then stop it after the check:
   ```bash
   kubectl port-forward --address 127.0.0.1 -n authentik svc/authentik-server 9000:80
   ```
   Open `http://127.0.0.1:9000/` while the command runs. Do not bind the port-forward to a LAN or public interface. Do not use the initial-setup flow to replace an existing administrator or database.
3. Confirm the administrator recovery method is controlled and available before making identity changes. Verify access to the approved recovery factor or stored recovery codes without copying credentials into Git, chat, logs, or this runbook. If initial setup is still incomplete, the account is unavailable, or recovery is uncertain, stop and use the approved Authentik recovery procedure. Do not reset credentials, expose reset links, or perform database recovery as part of service onboarding. The separate [cluster recovery runbook](cluster-recovery.md#phase-4--cnpg-database-recovery) is a stop boundary, not an Authentik restore procedure.
4. Decide which user identities and groups may access this service, who owns the application account mapping, and how to roll back only this service's route or authentication configuration.

## Users, groups, and application bindings

Use Authentik groups to express authorization separately from how users sign in. The shared `homelab-allowlist` group is a starting point for identities approved to use Homelab services. Prefer a narrower group such as `service-name-users` when a service has a smaller or different audience. Keep administrators and service users distinct where practical. Add only verified, intended identities; do not treat successful Google or GitHub sign-in as authorization by itself.

Create an Authentik Application for each service and bind it to the intended group or policy before relying on the gate. **An Application with no bindings allows access by default.** Verify the binding on the actual Application, not just the provider, then test both an allowed user and a signed-in user who is not in the group. Also test what an unauthenticated visitor sees. Do not onboard a production service with an unbound Application.

For every integration, record the service owner, allowed group, provider type, exact external URL and callback URI, the secret storage reference (not its value), and the tested rollback. Review existing accounts and administrator ownership before changing how users are created or linked.

## Native OIDC integration

Use the application's native OIDC support when the application officially supports it. Authentik then acts as the identity provider, and the application validates OIDC tokens and creates or maps its own local accounts. This is different from Forward auth, which is only a Traefik HTTP access gate.

1. Read the vendor's current authentication guide for the deployed application version. Confirm supported OIDC flows, discovery URL, exact callback path, claim and group mapping, logout behavior, and whether the server must reach Authentik endpoints directly. Do not guess the callback URI or infer it from the public host.
2. Create an Authentik OAuth2/OpenID provider and Application for the service. Configure the **exact** redirect URI published by the vendor, including scheme, host, path, and trailing slash if specified. For the previously documented Karakeep version, the example callback is `https://karakeep.leehosanganson.dev/api/auth/callback/custom`; verify it against the deployed version before use. The discovery URL is not the callback URL.
3. Bind the Authentik Application to `homelab-allowlist` or the approved service-specific group. Test allowed and denied users before changing application settings.
4. Store the client secret in Azure Key Vault using the repository's approved secret workflow. Add or update the application's `ExternalSecret` in its environment overlay to fetch that key into the Kubernetes Secret consumed by the app. Keep credentials out of Git, ConfigMaps, command output, logs, and chat. Follow the app's existing pattern; do not create missing Key Vault values or introduce a new secret mechanism as part of an unapproved onboarding.
5. Configure the application with its vendor-documented discovery URL, client ID, and client secret. Preserve the existing local sign-in and account-recovery paths while testing. **Do not disable local authentication, disable sign-ups, or enable automatic email account linking until existing accounts, verified email ownership, administrator mapping, recovery, and lockout behavior have been reviewed and tested.** In particular, never enable a dangerous email-linking option just to make an existing account match an OIDC identity.
6. Test sign-in and sign-out, callback and session behavior, allowed and denied accounts, duplicate or existing accounts, recovery, and the service's browser, API, mobile, and automation clients. Confirm both the browser and application server can reach the endpoints they need. Document any remaining local-auth bypass or session behavior; group removal does not necessarily revoke an existing application session.

Keep native OIDC manifests and secret references in the service directory. Use the vendor callback on the application itself; do not add a Traefik ForwardAuth middleware or Authentik outpost callback for native OIDC. This guide does not activate a new OIDC integration.

Authentik Proxy Provider's Forward auth (domain level) can reduce the number of ForwardAuth providers across a shared parent domain, but it cannot enforce separate application-level policies for each service. See the [Forward auth section](#forward-auth-for-http-services) for details.

## Forward auth for HTTP services

Use this only when a service does not provide suitable native SSO and its HTTP requests pass through Traefik. Create an Authentik **Proxy Provider** using **Forward auth (single application)**, attach it to the service's Authentik Application, and use the embedded outpost. The embedded outpost is served by the Authentik server; the address below uses the in-cluster Service port `80` (which forwards to the server's port `9000`).

Forward auth requires Traefik's Kubernetes CRD provider and both the `Middleware` and `IngressRoute` CRDs, even if the app keeps a standard Kubernetes Ingress: the outpost callback uses an IngressRoute. At the last live check on 2026-11-23, Traefik `v3.7.19` had the CRD provider enabled, `allowCrossNamespace: false`, and external-name Services disabled; the Middleware CRD was installed. Git declares `providers.kubernetesCRD.enabled: true` and `allowCrossNamespace: false`, and the pinned Traefik HelmRelease sets `install.crds: Create` and `upgrade.crds: CreateReplace`; still verify that the required CRDs are installed and the provider is configured as expected on the target cluster before relying on them:

```bash
helm get values traefik -n kube-system --all \
  | yq '.providers.kubernetesCRD | {enabled, namespaces, allowCrossNamespace, allowExternalNameServices}'
kubectl get crd middlewares.traefik.io ingressroutes.traefik.io
```

Stop if the CRD provider is disabled, either CRD is missing, or a non-empty provider `namespaces` allowlist excludes either the service or `authentik` namespace (an empty list means all namespaces). Do not assume that an Ingress in one namespace can reference a Middleware in another, or that a Kubernetes `ExternalName` Service is a workaround.

Starting Middleware only; it does not create or route the application, Authentik Application, provider, outpost, or callback endpoint:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: service-authentik-forward-auth
  namespace: service-namespace
spec:
  forwardAuth:
    address: http://authentik-server.authentik.svc.cluster.local:80/outpost.goauthentik.io/auth/traefik
    maxResponseBodySize: 4194304
```

Replace `service-namespace` and the Middleware name. Keep the Middleware in the app namespace and attach it only to the protected app route:

- For an existing Kubernetes Ingress, use `traefik.ingress.kubernetes.io/router.middlewares: <namespace>-<middleware-name>@kubernetescrd`.
- For a Traefik IngressRoute, reference the local Middleware by name under `spec.routes[].middlewares` on the app route. Do not leave an old Ingress serving the app alongside its replacement.

Do not apply this YAML directly to the cluster. Confirm its API version and schema against the installed Traefik CRD before a future PR.

**Single-application callback requirement:** Route `/outpost.goauthentik.io/` on the protected app host to `authentik-server` on port `80` without middleware. Give this route priority over the protected app route for that path, or sign-in can fail or loop. Set `metadata.namespace: authentik` on the callback IngressRoute so it can reach the local outpost Service without allowing cross-namespace references.

**IngressRoute TLS:** For an app IngressRoute, declare an explicit cert-manager `Certificate` for the app host and set the route's `spec.tls.secretName` to the Certificate's `spec.secretName`. The route, Certificate, and resulting Secret must be in the same namespace. Ingress-shim does not generate Certificates from IngressRoute resources. Do not reference the app's Secret from the callback namespace; verify TLS on the shared hostname for both routes in the pilot.

**Certificate cutover:** When replacing an Ingress that uses Ingress-shim with an IngressRoute and an explicit Certificate, verify after authorized Flux reconciliation that the Certificate is `Ready=True`, its `metadata.ownerReferences` no longer point to the old Ingress, and the intended TLS Secret still exists in the service namespace. Flux may recreate the Certificate object on a later retry, so recheck after any retry. A surviving TLS Secret alone does not prove that cert-manager will continue renewing the certificate.

**Plain HTTP:** An IngressRoute that uses only the `websecure` entry point does not serve plain HTTP. Plain HTTP is not redirected to HTTPS unless a separate Traefik redirect is configured.

Forward auth gates only HTTP requests that traverse Traefik. It does not make the application speak OIDC, validate Authentik identity, or trust identity headers. Do not add or trust identity headers unless the application explicitly supports that model and a separate review establishes the trusted proxy boundary and prevents client-supplied spoofing. Direct access to the application Service, another Ingress, a load balancer, or another network path can bypass the gate. Verify those paths are closed or intentionally controlled.

Before a wider rollout, run a reviewed **single-service pilot** and verify all of these:

- The Authentik Application is bound to the intended group; an allowed user passes and a denied user is blocked.
- Unauthenticated login redirects and return to the app work without loops. The callback path reaches the outpost and is not itself protected by the ForwardAuth middleware.
- Traefik selects the intended host/path routes, callback route priority is correct, and TLS works for both app and callback requests.
- Test a plain `http://` request to the service hostname. For a `websecure`-only IngressRoute, confirm that it does not serve the app and redirects to the intended `https://` URL only if a separate Traefik redirect is configured.
- The normal app page, API calls, WebSockets if used, health checks, and browser/mobile/automation clients behave as intended. Do not accidentally block health checks or clients that cannot follow an interactive login.
- The backend cannot be reached around the Traefik gate, or any direct path has a documented independent control.
- The reviewed rollback keeps this service offline without changing Authentik's own Ingress or other services.

A successful browser redirect alone is not sufficient evidence. Do not extend Forward auth to other services until every pilot check passes and the service owner accepts the effect on its clients.

## GitOps change and verification

Keep all integration files under the service directory. The [production apps bundle](../../kubernetes/apps/overlays/production/kustomization.yaml) continues to include the service's existing default overlay under [`apps-production`](../../fluxcd/clusters/production/apps.yaml). Do not add a separate production entry or a child Flux Kustomization.

For Forward auth only:

1. Keep the protected app route, Middleware, direct-access controls, and (for an app IngressRoute) explicit Certificate at the root of the service's default overlay. Set `metadata.namespace` to the app namespace in each file. Keep the base namespace-neutral and use targeted patches in the default overlay to set the namespace of resources from the base, such as the Deployment and Service.
2. Keep `callback-ingressroute.yaml` in the same directory and set `metadata.namespace: authentik` explicitly in that file.
3. In the default overlay's `kustomization.yaml`, list the base and each overlay file directly under `resources`. Do not set a top-level `namespace:`; it could move the callback into the app namespace.

For native OIDC, use the vendor callback on the application and keep only the OIDC secret references and configuration in the service overlay. Do not add a Traefik ForwardAuth middleware or Authentik outpost callback.

The `flux-validate` workflow builds and schema-checks the production bundle. Review the rendered namespaces, TLS Secret reference, and, for Forward auth, the middleware attachment before merge; schema validation does not verify live routing or access.

Open a focused PR with one service's Authentik provider/application instructions and app-side configuration. Include the vendor guide/version, exact callback URI, intended group, secret **reference only**, ForwardAuth/callback routing design if used, pilot results, and rollback steps. Validate the affected Kustomize overlay and inspect the rendered resources before merge. Follow [the repository testing and validation workflow](workflows-testing-validation.md) only when its branch-testing procedure is approved; it temporarily makes all Flux Kustomizations track a PR branch, so it is not a narrow per-service test. After merge, use normal Flux reconciliation and verify the affected resources and service behavior. Do not make live cluster mutations as a substitute for a PR.

## Rollback and safety limits

For a Forward auth pilot, take only the affected service offline through a reviewed Git change. Disable its app route and keep its NetworkPolicy or other direct-access controls. Verify no route still serves the app before removing the callback or auth resources. Removing callback manifests from the service overlay can cause `apps-production` to prune the callback route. Switching the shared Flux source can also prune the route and restore an unauthenticated app route. Before any source switch, render the exact destination revision and confirm it keeps the service offline; if you cannot verify that, do not switch. Check live routes after authorized reconciliation before restoring service with a verified access-controlled configuration.

For native OIDC, restore only the affected application's last known-good authentication settings and secret references. Do not delete the Authentik user, provider, Application, database, backups, or shared groups as an application rollback. Do not change or disable Authentik's own ingress gate, remove Authentik from its Flux inventory, or edit Authentik/database resources as part of a service rollback. Any identity database or Authentik recovery is outside this runbook and requires its own reviewed recovery plan.

## References

- [Authentik first steps](https://docs.goauthentik.io/install-config/first-steps/) — applications, providers, and initial configuration.
- [Authentik OAuth2/OpenID Connect provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/) — native OIDC provider setup.
- [Authentik policy bindings](https://docs.goauthentik.io/customize/policies/bindings/) — bindings and policy evaluation.
- [Authentik Proxy Provider](https://docs.goauthentik.io/add-secure-apps/providers/proxy/) — proxy provider modes and configuration.
- [Authentik embedded outpost](https://docs.goauthentik.io/add-secure-apps/outposts/embedded/) — embedded outpost behavior.
- [Traefik ForwardAuth](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/forwardauth/) — ForwardAuth middleware fields and behavior.
- [Traefik Kubernetes CRD provider](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-crd/) — provider namespace and resource configuration.
- [Traefik Kubernetes Middleware CRD](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/crd/http/middleware/) — Middleware resource fields and behavior.
- [Existing Homelab Authentik SSO runbook](authentik-sso.md) — installation, ingress, access, and recovery.
- [Cluster recovery runbook](cluster-recovery.md) — recovery stop boundary; not an executable Authentik restore procedure.
- [Testing and validation runbook](workflows-testing-validation.md) — PR-branch Flux test procedure and its scope.
