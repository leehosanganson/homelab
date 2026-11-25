# Adopt the CloudNativePG operator into Flux

Merging this change will apply the vendored CloudNativePG (CNPG) 1.27.0
operator through [infra-production][flux] on its next reconcile. The live tag
and the pinned digest use different image strings, so the operator could roll
even if both refer to the same image. Barman and database workloads are out of
scope.

1. Before merging, use approved production access to review the actual Flux
   server-side apply diff. Check the Deployment pod template, Flux inventory,
   and field ownership. Confirm that apply preserves the live-managed webhook CA
   bundles and their current ownership. Stop on unexpected changes or unresolved
   ownership conflicts; do not copy live CA values into Git.
2. After merge, verify that `infra-production` is ready and owns the operator,
   the Deployment and webhooks are healthy, and database workloads are unchanged.
3. If reverting, the per-resource prune annotation tells Flux to leave CNPG
   objects, including its CRDs, in place. A revert does not uninstall CNPG or
   restore its previous live fields.

[flux]: ../../fluxcd/clusters/production/infra.yaml
