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
  | yq '.providers.kubernetesCRD | {
      "enabled": .enabled,
      "namespaces": .namespaces,
      "allowCrossNamespace": .allowCrossNamespace,
      "allowExternalNameServices": .allowExternalNameServices
    }'
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

**Certificate cutover:** Do not prune an Ingress while it still owns a Certificate you need to keep. A same-name Certificate manifest does not remove the Ingress owner reference, and a surviving TLS Secret does not prove that the original Certificate survived. For Mini QR, follow the [staged cutover gate](#mini-qr-staged-cutover-gate) before applying the final overlay.

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

Open a focused PR with one service's Authentik provider/application instructions and app-side configuration. Include the vendor guide/version, exact callback URI, intended group, secret **reference only**, ForwardAuth/callback routing design if used, pilot results, and rollback steps. Validate the affected Kustomize overlay and inspect the rendered resources before merge. **For Mini QR production, follow only the [staged cutover gate](#mini-qr-staged-cutover-gate).** For other services, use the [repository branch-testing procedure](workflows-testing-validation.md) only when approved: it temporarily makes all Flux Kustomizations track a PR branch. After merge, use normal Flux reconciliation and verify the affected resources and service behavior. Do not make live cluster mutations as a substitute for a PR.

## Mini QR staged cutover gate

**The only production cutover path is the four stages below.** Ship each stage as its own reviewed PR, squash-merged to `main`. Keep Flux tracking `main` throughout. No PR-branch Flux test, source switch, or one-step merge is allowed for this cutover. After each merge, record the resulting main commit SHA and wait for `apps-production` in `flux-system` to report that exact SHA in `.status.lastAppliedRevision` with `Ready=True` for its current generation. An artifact revision, attempted revision, or Ready on a different SHA does not count. Do not merge the next stage until that revision and all its stage checks pass. Stop if Flux skips a required SHA.

Mini QR downtime is accepted; keep the existing Certificate and TLS Secret. Pruning the old Ingress before orphaning can garbage-collect its Certificate, and Flux may recreate the Certificate with the same name but a different UID. Router priority does not protect legacy plain HTTP or prevent bypass if Traefik skips a new router.

Before the first merge, confirm the production Kubernetes context and the live `utility/mini-qr` Ingress and `utility/mini-qr-tls` Certificate and Secret. Record their UIDs, ownership links, Certificate spec and revision, and the leaf certificate fingerprint. Never print or export the private key; use only metadata and the public leaf certificate. Require a ready Certificate, no issuance in progress, and enough time before renewal for the maintenance window. Stop if ownership, issuance, or the planned Certificate spec is unexpected. Confirm that you can obtain the per-replica inventory described below before starting downtime.

1. **Route-off:** Keep the legacy Ingress object and its TLS stanza. Remove its ingress-shim issuer trigger and any legacy `kubernetes.io/ingress.class` annotation, set `spec.ingressClassName` to an unused class verified not to be handled by any controller, and set `kustomize.toolkit.fluxcd.io/prune: disabled` on that Ingress. Include the Mini QR NetworkPolicy, but not the explicit Certificate or either replacement route. After the exact revision is Ready, pass the [route-off proof](#mini-qr-route-off-proof) and confirm that the Certificate and Secret still have their original UIDs.
2. **Orphan:** Omit the Ingress from Git; keep the NetworkPolicy and leave the explicit Certificate and both routes out. After the exact revision is Ready, confirm Flux dropped the Ingress from inventory but the same disabled, prune-exempt Ingress is still live. Repeat the route-off proof, then use the [guarded orphan delete](#mini-qr-guarded-orphan-delete) with separate approval. Wait until the Ingress is gone and its UID is absent from the Certificate's owner references. Verify the original Certificate and Secret UIDs, Certificate revision and leaf fingerprint. Do not use normal pruning or delete the Certificate or Secret.
3. **Certificate adoption, routes off:** Add the explicit Certificate, not the routes. Before merging, compare the live Certificate spec with a server-side dry run under Flux's apply semantics, including defaults. Stop if the effective spec would change or trigger issuance. Once the exact revision is Ready, confirm `apps-production` inventories the Certificate, it is `Ready=True` without issuance in progress, the original UIDs, Certificate revision and leaf fingerprint are unchanged, and the route-off proof still passes. Record this revision as the rollback target.
4. **Route activation ([#1254](https://github.com/leehosanganson/homelab/pull/1254)):** Keep this final PR blocked until the three preceding stages and their live checks pass. Review its diff against the adopted main state and confirm Authentik preflight and group binding before merging. After the exact activation revision is Ready, verify on each Traefik replica that the legacy router is absent, HTTP cannot serve Mini QR, HTTPS requires authentication, and the callback path reaches Authentik without ForwardAuth. Run the full pilot with normal certificate validation (no `-k` or browser warning override) for both app and callback, and confirm the served fingerprint.

**Rollback after adoption:** On activation failure, use a reviewed PR to restore Mini QR to the exact Certificate-adopted/routes-off configuration from stage 3, keeping the Certificate, TLS Secret and NetworkPolicy. Verify the rollback main SHA is Ready and repeat the route-off proof. Before adoption, stop at the failed gate for review. Never source-switch or revert to any revision that restores the unprotected Ingress.

### Mini QR route-off proof

Enumerate the Traefik pods in `kube-system` with selector `app.kubernetes.io/instance=traefik-kube-system,app.kubernetes.io/name=traefik`. Inspect **each pod's effective runtime router inventory** (including HTTP and TCP, across providers). Require no Mini QR app or callback router. Check wildcard and catch-all rules too: no matching router may send requests for this host to Mini QR, the outpost, or another backend. Only a verified entry-point redirect is acceptable. A Kubernetes manifest list is not a runtime inventory. Repeat for any replicas replaced during verification.

The [pinned chart 43.0.0 defaults](https://github.com/traefik/traefik-helm-chart/blob/v43.0.0/traefik/values.yaml) and this repo enable the dashboard feature, not an API route: the dashboard IngressRoute is off, insecure API is not enabled, and the admin entry point `traefik` (8080) is not exposed by the Service. A port-forward alone does not make `/api/rawdata` available. Obtain a fresh per-pod runtime config snapshot through an approved internal diagnostic path, or arrange one in advance through separate review: the chart supports an `api@internal` dashboard route restricted to `traefik`. If using that option, require access controls against other workloads, no Service/public exposure or insecure API, and a loopback-only pod port-forward (add `18080:8080` below). Fetch `http://127.0.0.1:18080/api/rawdata` through that approved route and inspect `routers` and `tcpRouters`. Stop if an authoritative inventory is unavailable for any replica.

Forward to **one pod at a time**, not the load-balanced Service. Set `POD` to that pod's name and `PROD_CONTEXT` to the verified production kubeconfig context. Run on a trusted workstation:

```bash
kubectl --context "${PROD_CONTEXT:?}" -n kube-system port-forward \
  --address 127.0.0.1 "pod/${POD:?}" 18000:8000 18443:8443
```

In another terminal, send HTTP requests for both the app and callback paths over plain HTTP and HTTPS. `--connect-to` preserves the URL hostname for the HTTP Host header and TLS SNI while dialing the forwarded port:

```bash
host=qr.homelab.leehosanganson.dev
for path in / /outpost.goauthentik.io/; do
  curl -q --noproxy '*' --max-time 10 -si --connect-to "$host:80:127.0.0.1:18000" "http://$host$path"
  curl -q --noproxy '*' --max-time 10 -ski --connect-to "$host:443:127.0.0.1:18443" "https://$host$path"
done
```

Expect Traefik's unrouted HTTP 404 on both paths and schemes, not an app/outpost response, auth redirect, or upstream error. If a separately verified entry-point redirect exists, HTTP may redirect to the same host on HTTPS, which must still return the unrouted 404. HTTPS here uses `-k` only to let curl send HTTP even with a fallback certificate; a TLS handshake or certificate error alone is inconclusive, not a pass. Close each port-forward when done. Repeat the host probes through the normal LAN entry point and check any alternate access paths; none may serve Mini QR while routes are off.

### Mini QR guarded orphan delete

Local `kubectl delete` (v1.37.1) cannot send both preconditions. Use a JSON `DeleteOptions` body so the API server checks the approved Ingress UID **and** resourceVersion atomically. Do not use a name-only delete or refresh the preconditions on failure.

On a trusted workstation, set `PROD_CONTEXT` to the verified production kubeconfig context. In one terminal start a loopback-only proxy restricted to the single Ingress path. Use the port it reports and keep the proxy running only for this step:

```bash
kubectl --context "${PROD_CONTEXT:?set the verified production context}" proxy \
  --address=127.0.0.1 --port=0 \
  --accept-paths='^/apis/networking[.]k8s[.]io/v1/namespaces/utility/ingresses/mini-qr$' \
  --reject-methods='^(POST|PUT|PATCH|CONNECT)$'
```

In another terminal set `PROXY_PORT` to that port, `INGRESS_UID` to the original recorded UID, and `OFF_CLASS` to the reviewed unused class. This reads only the Ingress, checks key invariants, and shows the target, spec and exact request body for review. Confirm the spec matches stage 2, including the unchanged TLS stanza and confirm orphan-delete approval before typing `orphan mini-qr`. The command sends the same reviewed body, not one built from a fresh GET.

```bash
(
  set -euo pipefail
  url="http://127.0.0.1:${PROXY_PORT:?set the proxy port}/apis/networking.k8s.io/v1/namespaces/utility/ingresses/mini-qr"
  ingress=$(curl -q --noproxy '*' --max-time 15 -fsS "$url")
  options=$(jq -e --arg uid "${INGRESS_UID:?set the recorded UID}" \
    --arg class "${OFF_CLASS:?set the reviewed unused class}" '
    select(.apiVersion == "networking.k8s.io/v1" and .kind == "Ingress"
      and .metadata.namespace == "utility" and .metadata.name == "mini-qr"
      and .metadata.uid == $uid and .metadata.deletionTimestamp == null
      and .spec.ingressClassName == $class
      and .metadata.annotations["kubernetes.io/ingress.class"] == null
      and .metadata.annotations["kustomize.toolkit.fluxcd.io/prune"] == "disabled"
      and .metadata.annotations["cert-manager.io/cluster-issuer"] == null
      and .metadata.annotations["cert-manager.io/issuer"] == null
      and .metadata.annotations["kubernetes.io/tls-acme"] != "true"
      and (.metadata.resourceVersion | type == "string" and length > 0))
    | {apiVersion:"v1", kind:"DeleteOptions", propagationPolicy:"Orphan",
       preconditions:{uid:.metadata.uid, resourceVersion:.metadata.resourceVersion}}
  ' <<< "$ingress")
  jq '{metadata: (.metadata | {namespace, name, uid, resourceVersion}), spec}' <<< "$ingress"
  printf '%s\n' "$options"
  read -r -p 'Type "orphan mini-qr" only after review and approval: ' confirm
  [[ "$confirm" == 'orphan mini-qr' ]] || exit 1
  status=$(curl -q --noproxy '*' --max-time 15 -sS -o /dev/null -w '%{http_code}' \
    -X DELETE -H 'Content-Type: application/json' --data-binary "$options" "$url")
  case "$status" in
    200|202) printf 'Delete accepted (HTTP %s); verify orphaning.\n' "$status" ;;
    *) printf 'Stop: DELETE returned HTTP %s.\n' "$status" >&2; exit 1 ;;
  esac
)
```

Stop on any check failure, non-success response, or timeout. Stale preconditions return a conflict without deleting anything. A timeout can leave the result unknown: inspect live state before deciding what happened. Do not retry automatically, bypass preconditions, or fall back to a plain delete. Stop the proxy and finish the stage 2 ownership and preservation checks before advancing.

## Rollback and safety limits

For Mini QR, use the [staged cutover rollback](#mini-qr-staged-cutover-gate), not a Flux source switch. For other Forward auth pilots, take only the affected service offline through a reviewed Git change. Disable its app route and keep its NetworkPolicy or other direct-access controls. Verify no route still serves the app before removing the callback or auth resources. Removing callback manifests from the service overlay can cause `apps-production` to prune the callback route. Switching the shared Flux source can also prune the route and restore an unauthenticated app route. Before any source switch, render the exact destination revision and confirm it keeps the service offline; if you cannot verify that, do not switch. Check live routes after authorized reconciliation before restoring service with a verified access-controlled configuration.

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
