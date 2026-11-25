---
name: authentik-service-onboarding
description: >-
  Plan and document onboarding a Homelab service to the existing Authentik
  installation with native OIDC or Traefik Forward auth. Use for a specific
  service integration; not for installing or recovering Authentik, operating
  Flux, or changing cluster resources without a scoped request.
---

## When

Use when planning or implementing a reviewed Authentik integration for one Homelab service. Do not use for Authentik installation, database recovery, general identity-provider questions, or broad proxy rollout.

## Strict

- Read and follow [the Authentik service onboarding runbook](../../../docs/runbooks/authentik-service-onboarding.md); it is the source of procedure and current repository context.
- Do not expose secrets, assume an unbound Authentik Application denies access, or claim Forward auth provides native OIDC or protects direct backend paths.
- Do not disable local login, enable automatic email linking, change Authentik's own ingress, or make live cluster mutations as part of onboarding.
- Keep the callback IngressRoute and its outpost Service in `authentik`. Do not assume the callback works until a single-service pilot verifies it.

## Steps

1. For an authorized onboarding, verify Authentik health, administrator sign-in, and recovery readiness using the runbook's safe preflight. For Forward auth, also verify the Traefik CRD provider and both required CRDs. For worktree-only changes, leave live checks pending.
2. Select native OIDC when the service supports it; otherwise assess Traefik Forward auth and its callback route requirements.
3. Confirm the service owner, exact callback URI (if OIDC), allowed group, secret reference, affected clients, bypass paths, pilot checks, and service-scoped rollback.
4. Keep the approved GitOps files under the service directory. For Forward auth, attach the local Middleware via the app Ingress annotation or the IngressRoute app route. For an app IngressRoute, use an explicit cert-manager Certificate and its Secret in the same namespace; ingress-shim does not handle IngressRoute. Route the callback to the outpost without middleware. Include the app overlay and callback path directly from the namespace-neutral service overlay root under the existing `apps-production`; do not add a child Flux Kustomization or a central registration. For native OIDC, use the vendor callback and service-local ExternalSecret reference; preserve local login.
5. Inspect the app and callback in the rendered production apps bundle using the runbook's checks. Run live preflight or pilot checks only when separately authorized.

## Asks You?

Ask when account ownership, access groups, callback details, network exposure, or rollback is unclear. Otherwise proceed within the approved service scope and record assumptions.

## Output

Provide the service's chosen integration path, exact verified callback or route design, group and secret references (never secret values), checks and results, limitations, and service-only rollback steps.

## Best Size

One service at a time. Split broad onboarding into separate reviewed service changes; route installation, identity-database recovery, and cluster operations to their own workflows.

## Speed

Use the runbook and the deployed service's vendor guide/version. Do not repeat Authentik installation checks or test unrelated services.

## Edge

If the operator account or recovery method is uncertain, stop before identity changes. For Forward auth, do not expand beyond the pilot until callback routing, TLS/route priority, denial, health/API/client behavior, and direct-backend bypass checks pass.
