# Adopt the CloudNativePG operator into Flux

The [production Flux Kustomization][flux] points to the vendored CloudNativePG
(CNPG) 1.27.0 operator bundle, pinned by image digest. It starts suspended:
merging this change does not adopt or upgrade the operator. Pruning and forced
replacement are disabled, and deleting the Kustomization leaves its resources
in place. Barman and database workloads are outside its scope.

## Before removing suspend in a separate activation PR

1. With approved cluster access, review actual Flux server-side apply behavior
   for the candidate against live objects. Check Flux inventories and field
   ownership, and review the resulting changes, not just the offline render.
   Stop on unexpected changes or unresolved ownership conflicts.
2. Resolve image and pod-template drift. The live tag and the vendored digest
   match the same image hash, but Flux sees different image strings and a
   different pod template, which may trigger a rollout. Account for the live
   `kubectl.kubernetes.io/restartedAt` annotation without copying it into Git.
3. Verify Flux will preserve the live-managed webhook CA bundles and leave
   certificate ownership with its current manager. The vendored bundle contains
   no `caBundle` placeholder; do not copy live CA values into Git.
4. Remove `suspend` only once drift and ownership are resolved and the expected
   changes are approved. After activation, verify Flux inventory and readiness,
   operator rollout and webhook health, and unchanged database workloads. Do not
   assume the first reconcile is a no-op. Bump the operator version in a later,
   separate PR after adoption is verified.

[flux]: ../../fluxcd/clusters/production/cnpg-operator.yaml
