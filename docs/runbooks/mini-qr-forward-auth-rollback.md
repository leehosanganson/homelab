# Take the Mini QR ForwardAuth pilot offline

Use this runbook if sign-in, callback, or access checks fail, or when stopping the production pilot. Take the app off HTTPS without restoring its old unauthenticated route. This procedure keeps the backend in place; it does not decommission the app or change Cloudflare Tunnel routes.

## Before you start

Confirm the production Kubernetes context with `kubectl config current-context`. You need approval to take the pilot offline, Git and Kustomize to review and render exact revisions, and Flux and `kubectl` access to reconcile and inspect production. You must be able to list Ingresses and Traefik IngressRoutes across all namespaces. Use the hostname in the [base Ingress](../../kubernetes/apps/mini-qr/base/ingress.yaml) when reviewing routes.

The [Mini QR overlay](../../kubernetes/apps/mini-qr/overlays/default/kustomization.yaml) includes the base Ingress via `../../base` and separately lists the Middleware and NetworkPolicy. [`apps-production`](../../fluxcd/clusters/production/apps.yaml) owns these resources in `utility`. [`infra-production`](../../fluxcd/clusters/production/infra.yaml) owns the separate [`mini-qr-outpost` callback IngressRoute](../../kubernetes/infra/authentik/overlays/default/ingressroute.yaml) in `authentik`. Both Flux Kustomizations reconcile independently with `prune: true`. Use two successive reviewed Git changes so cleanup cannot run before the app is verified offline.

**Before any Flux source switch:** Render the exact destination revision from a local copy. Use `kustomize build kubernetes/apps/overlays/production` from that revision's repository root to verify the delete patch still takes effect and the Mini QR Ingress remains absent. Do not use the [PR-testing instructions to return Flux to `main`](workflows-testing-validation.md#5-revert-to-main-when-done) unless the exact `main` revision passes this check and keeps the app offline. Switching away from an unmerged rollback can drop its delete patch and restore the baseline unauthenticated Ingress. If the destination cannot be verified or would restore the route, keep Flux on the reviewed offline revision or get a separate approved offline change into the destination first, then render it again.

## Take the app offline, then clean up

1. In the Mini QR overlay, replace the current Ingress annotation patch with this delete patch. Keep the base, Middleware, and NetworkPolicy references. Do not just strip the middleware annotation or revert to an unauthenticated Ingress.

   ```yaml
   patches:
     - patch: |-
         $patch: delete
         apiVersion: networking.k8s.io/v1
         kind: Ingress
         metadata:
           name: mini-qr
   ```

   Before the change enters the Flux source, run `kustomize build kubernetes/apps/mini-qr/overlays/default` from the repository root. Confirm there is no Mini QR Ingress and the Deployment, Service, NetworkPolicy, and Middleware remain.
2. Reconcile `apps-production` in `flux-system` against the reviewed offline revision. From the production context, run:

   ```bash
   flux get kustomizations apps-production -n flux-system
   kubectl get ingress mini-qr -n utility
   kubectl get ingresses.networking.k8s.io -A -o yaml
   kubectl get ingressroutes.traefik.io -A -o yaml
   kubectl get networkpolicy mini-qr-ingress -n utility -o yaml
   ```

   Require `apps-production` to be Ready at the exact reviewed revision and the named Ingress lookup to report `NotFound`. Inspect all Ingress and IngressRoute rules for the hostname and for backends that route to Mini QR, including wildcard or catch-all rules and default backends. No route may serve Mini QR. Before cleanup, the only expected route for the hostname is `authentik/mini-qr-outpost`, restricted to `/outpost.goauthentik.io/` and pointing only to `authentik-server`. Verify the `mini-qr-ingress` NetworkPolicy still matches the reviewed policy. If a check fails or cannot be completed, stop and escalate without removing the auth resources.

   An HTTPS check from a trusted LAN client is optional. The deleted Ingress owns `mini-qr-tls`, so the hostname may no longer present a trusted certificate. A certificate validation failure is inconclusive, not proof that the app is offline. Never disable TLS validation to pass this check. If HTTPS still serves Mini QR, stop and investigate. These checks do not establish external reachability through Cloudflare Tunnel.
3. Only after offline verification, make a second reviewed Git change. Keep the delete patch, remove the callback `ingressroute.yaml` from the [Authentik overlay](../../kubernetes/infra/authentik/overlays/default/kustomization.yaml), and remove `middleware.yaml` from the Mini QR overlay after confirming nothing else references it. Render both affected overlays before review. Reconcile `infra-production` and `apps-production` as needed, then verify both are Ready at the exact cleanup revision and have pruned the callback and Middleware. Repeat the Ingress, IngressRoute, and NetworkPolicy checks from step 2; the callback exception no longer applies. Keep the Deployment, Service, and `mini-qr-ingress` NetworkPolicy unless a separate reviewed decommission removes the app. If verification fails, keep the delete patch in place and escalate.

## Restart only after review

Keep the app offline until a separate review approves a restricted pilot restart. Verify that the callback and Middleware are ready before restoring the Ingress with ForwardAuth attached. Keep the NetworkPolicy in place. Before reopening normal access, verify that the callback and sign-in work, an approved user reaches the app, signed-out and unauthorized users cannot, and direct backend access from outside the allowed Traefik pods is blocked. If any check fails or is inconclusive, take the app offline again using this runbook.
