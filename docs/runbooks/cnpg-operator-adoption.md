# Adopt the CloudNativePG operator into Flux

Merging [#1268](https://github.com/leehosanganson/homelab/pull/1268) applied the vendored CloudNativePG (CNPG) 1.27.0 operator through [infra-production][flux]. The change pinned the operator image without changing Barman or database workloads.

1. Before merging, use approved production access to review the actual Flux server-side apply diff. Check the Deployment pod template, Flux inventory, and field ownership. Confirm that apply preserves the live-managed webhook CA bundles and their current ownership. Stop on unexpected changes or unresolved ownership conflicts; do not copy live CA values into Git.
2. After merge, verify that `infra-production` is ready and owns the operator, the Deployment and webhooks are healthy, and database workloads are unchanged.
3. If reverting, the per-resource prune annotation tells Flux to leave CNPG objects, including its CRDs, in place. A revert does not uninstall CNPG or restore its previous live fields.

## First upgrade hop: 1.27.0 to 1.28.4

This is an operator-only hop. The [upstream release manifest](https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v1.28.4/cnpg-1.28.4.yaml) is vendored unchanged (SHA-256: `8f24b9163df8ff771fc398de885e6c4052f31a1289f921f9d23024eff5e8ebbe`). The production overlay pins the manager image index and uses the same reference for `OPERATOR_IMAGE_NAME` in the named operator ConfigMap. CNPG uses that reference for database pod, job and PgBouncer bootstrap containers; keep both pins in sync. CNPG can roll database pods or update their instance managers even though the PostgreSQL image references and default (`ghcr.io/cloudnative-pg/postgresql:17.5`) are unchanged. The 1.28 series is no longer supported upstream; treat it as an intermediate hop.

- Merge only in an approved maintenance window: Flux reconciles automatically. Review the live server-side apply diff, inventory and webhook CA field ownership. Stop on a CA change, unresolved ownership conflict or unexpected diff; never copy live CA values into Git.
- Before merging, use approved access to check only whether the `cnpg-system/cnpg-controller-manager-config` Secret contains `POSTGRES_IMAGE_NAME` or `OPERATOR_IMAGE_NAME`. The Secret takes precedence over the ConfigMap. Stop if either key is present or the check is inconclusive; resolve overrides through the Secret owner. Do not print, log or copy Secret values.
- A bare Git revert is not a database rollback: it cannot undo instance-manager updates or restore database state. Before merging, require an approved recovery procedure with verified backups and write-ahead logs (WAL), restore to a separate cluster, and application cutover. See [CNPG database recovery](cluster-recovery.md#phase-4--cnpg-database-recovery) for planning guidance.
- Rehearse backup, WAL archiving and point-in-time recovery (PITR) with CNPG 1.28.4 and the unchanged Barman Cloud plugin 0.7.0 in an isolated environment before merging. Verify that bootstrap containers use the pinned image. Include a restore of Immich with its existing image and extensions. Keep rehearsal writes separate from production backup storage.
- After reconciliation, check Flux ownership, operator and webhook health, the effective PostgreSQL default, all eight database clusters and WAL archiving before closing maintenance. Do not use the hibernation helper until the operator and plugin meet its 1.28.x guard.

[flux]: ../../fluxcd/clusters/production/infra.yaml
