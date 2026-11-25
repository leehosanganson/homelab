# Upgrade the manual CloudNativePG operator to 1.28.4

**Candidate only; not approved for deployment.** Upgrade the manual operator in
`cnpg-system` from 1.27.0 to 1.28.4 on homelab K3s. Do not adopt it into Flux or
change the Barman plugin, PostgreSQL images, or application manifests in this
hop. Do not use this procedure for a fresh install, restore, or whole-site outage.

## 1. Verify the candidate and starting state

- Use a trusted admin workstation with `kubectl`, `curl` and `sha256sum`. Set
  `CTX` to the independently verified homelab context. Confirm the API server
  and K3s 1.35.6 baseline; use `--context="$CTX"` for every cluster command.
- Confirm the healthy 1.27.0 `cnpg-controller-manager` Deployment and Barman Cloud
  plugin v0.7.0 in `cnpg-system`. Verify manual operator ownership against live
  managed fields and Flux inventories. Record operator objects and customizations,
  webhook health, plugin registration/TLS, and all eight Cluster namespace/name
  pairs, primary and replica readiness, bound PVCs, and running/effective
  PostgreSQL images. Stop on inventory, health, or ownership drift, an active
  backup or recovery at cutover, or any ongoing failover or hibernation.
- Download the exact [v1.28.4 release manifest][asset] to a scratch file; set
  `UPSTREAM_MANIFEST` to its absolute path. Verify the source bytes:

  ```sh
  printf '%s  %s\n' '8f24b9163df8ff771fc398de885e6c4052f31a1289f921f9d23024eff5e8ebbe' "$UPSTREAM_MANIFEST" | sha256sum --check
  ```

  Require `OK`. The hash matches the [release asset metadata][asset-metadata]
  and the bytes match the [tagged source][tagged-manifest]. **Do not deploy the
  upstream file or release URL**, even if the checksum matches: the manager
  image tag is mutable. The [1.27.0 artifact][old] is not a rollback manifest.
- Offline comparison: all 25 resource identities match the 1.27 artifact; all
  10 custom resource definitions (CRDs) still serve and store `v1`. Webhook
  configurations and their Service are unchanged in the bundles. Review the CRD
  schema changes (including immutable cluster references), monitoring query
  changes and reduced metrics role privileges, and the added EndpointSlice
  read permissions. Review the [1.28 release notes][notes] and compare the
  candidate against live settings.
- Before starting the new operator anywhere, resolve and review the v1.28.4
  image digest from the upstream registry for the target platforms. Derive a
  separate deployable YAML from the verified bundle: in Deployment
  `cnpg-system/cnpg-controller-manager`, set the `manager` container image to
  its repository plus `@sha256:<reviewed-digest>`; do not patch the image after
  apply. Review the diff against the source; only that image field should
  change. Save the exact reviewed YAML as a read-only snapshot outside the
  GitOps tree. Record its SHA-256 and approved image reference with the review,
  including platform digests if it is an image index. Use only this snapshot
  for rehearsal, server dry-run, and apply. If the bytes change, repeat review
  and rehearsal; do not just update the checksum.

  Set `DEPLOY_MANIFEST` to the snapshot's absolute path and `DEPLOY_SHA256` to
  the SHA-256 from the review record, not one computed from the working copy.
  Define this check in the shell used for the following steps:

  ```sh
  verify_deploy_manifest() {
    printf '%s  %s\n' "$DEPLOY_SHA256" "$DEPLOY_MANIFEST" | sha256sum --check
  }
  ```

- The [1.28 compatibility docs][support] cover Kubernetes 1.35 and PostgreSQL
  17, but the new operator defaults to PG 18.4. Pinning the manager image does
  not pin database images. Most Cluster manifests here omit the image. For each
  Cluster, prove live and GitOps reconciliation preserve its PG17.5 image,
  including on restart or recreate. Stop if any depends on a changing default.
  Keep Immich on its [VectorChord image][immich] and verify that its recovery
  image also supplies `vchord.so`.

## 2. Close rehearsal gates before scheduling rollout

- **Barman and recovery:** The [v0.7.0 installation source][barman-install]
  specifies CNPG 1.26 or newer, same namespace, and cert-manager. That meets the
  documented version floor; the [v0.7.0 release notes][barman-notes] do not
  establish an exact 1.28.4 pairing. The tags depend on different CNPG-i
  versions (operator 0.5.0, plugin 0.3.0). Compatibility is not verified. Require
  a passing isolated rehearsal with the reviewed snapshot, plugin v0.7.0, and
  representative K3s, storage and PG17 settings. Run `verify_deploy_manifest`
  and stop on failure before applying the snapshot in rehearsal. Verify the
  manager image as in step 4, then test plugin discovery/TLS, base backup,
  WAL archiving, and point-in-time restore using both backup and WAL.
- **Recovery proof:** For each of the eight live Clusters, follow the active
  Barman WAL archiver in `spec.plugins` to its namespaced `ObjectStore`. Record
  the store, destination path, and effective `serverName` (including any
  default). Confirm fresh WAL and a fresh successful base backup from that
  Cluster in that archive; record the backup ID and WAL coverage through the
  recovery point. Recovery examples and `externalClusters` entries are not
  evidence of the active archive. Immich illustrates why: its configured active
  and example recovery server names differ. Stop if any evidence is missing or
  mismatched.
- Restore each database from its verified archive in isolation within agreed
  data-loss and recovery-time limits. For Immich, use the PG17.5 VectorChord
  image, verify `vchord` is installed and loaded, query a restored vector index,
  and smoke-test Immich. Use replacement Clusters and PVCs with no production
  traffic or writes to production archives. See the [recovery runbook][recovery];
  never change bootstrap on an initialized database.
- **Hibernate helper:** The [helper][helper] and [shutdown runbook][shutdown]
  remain restricted to 1.27.x. The upstream CLI hibernate source was unchanged
  between these tags, but the [1.28.4 reconciler][hibernate] reports
  `WaitingForHealthy` for unhealthy Clusters and leaves normal reconciliation
  running while it waits. Before operator rollout, require a separate reviewed
  1.28 helper/runbook change and isolated tests of on/off, readiness, retained
  PVCs, timeouts/cancellation, and the matching CLI/operator versions. Do not
  bypass the guard or use the 1.27 helper against 1.28.

## 3. Dry-run and apply only in approved maintenance

Obtain explicit maintenance approval after closing the gates above. Agree on
application impact, a time limit, and an incident owner; instance-manager updates
can restart or roll database pods. Use the reviewed manual server-side apply
(SSA) field manager for both commands; set `FIELD_MANAGER` to that name after
checking live ownership. Recheck the context, backup freshness, and cluster
health. Capture the live state and field ownership of every manifest object
before applying so partial changes can be identified.

```sh
verify_deploy_manifest &&
  kubectl --context="$CTX" apply --server-side --field-manager="$FIELD_MANAGER" \
    --dry-run=server -f "$DEPLOY_MANIFEST" -o yaml
```

**Stop** on a checksum failure, field conflict, API or admission error, object
creation, unexpected field change or removal, or risk to ownership or live
customizations. Confirm the dry-run still specifies the approved digest for
`manager`. Review webhook fields, CRDs, and monitoring settings against live
objects. A clean dry-run does not prove later reconciliation will work. Do not
use `--force-conflicts`, `--prune`, or delete/recreate objects to clear an error.

After dry-run review and maintenance approval, recheck and apply the snapshot
with the same context and field manager:

```sh
verify_deploy_manifest &&
  kubectl --context="$CTX" apply --server-side --field-manager="$FIELD_MANAGER" -f "$DEPLOY_MANIFEST" &&
  kubectl --context="$CTX" -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=5m
```

If verification, apply, rollout, or any post-check fails, stop and escalate to
the incident owner. If apply fails, skip the rollout check and inspect every
manifest object against the pre-apply record for partial changes before any
retry. Preserve logs, events, live revisions, CRD state and field ownership.
Do not reapply 1.27, run a Deployment-only undo, delete CRDs/PVCs, or force apply:
the CRDs and instance managers may already have changed. Resume only after a
review of actual state establishes a safe forward fix or a separately rehearsed
recovery into replacement Clusters and approved cutover.

## 4. Verify recovery of service before closing the window

- Confirm `cnpg-system/cnpg-controller-manager` is fully ready and its `manager`
  image matches the approved digest reference. Match the `manager` container's
  `imageID` on every current manager Pod to the approved digest (or the reviewed
  platform digest if pinned to an image index). Stop on a mismatch. Verify
  admission, operator/plugin logs and events, metrics scrapes, and custom queries.
- Confirm all eight original Clusters are healthy with their expected primary,
  ready instances, current instance managers, same PVCs, and unchanged PG17.5
  images. Verify application connectivity and reads/writes, including Immich
  VectorChord queries. For each Cluster, confirm fresh WAL and a successful
  Barman backup in its verified active archive before closing the window.
- Record evidence and schedule 1.29 and then 1.30 as separate reviewed hops,
  with fresh release, compatibility, recovery and hibernation checks at each
  hop. [Upstream recommends sequential upgrades][upgrade]; 1.28.4 is the
  [final 1.28 release][release], not a maintained stopping point.

[asset]: https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v1.28.4/cnpg-1.28.4.yaml
[asset-metadata]: https://api.github.com/repos/cloudnative-pg/cloudnative-pg/releases/tags/v1.28.4
[tagged-manifest]: https://github.com/cloudnative-pg/cloudnative-pg/blob/v1.28.4/releases/cnpg-1.28.4.yaml
[release]: https://github.com/cloudnative-pg/cloudnative-pg/releases/tag/v1.28.4
[notes]: https://cloudnative-pg.io/docs/1.28/release_notes/v1.28/
[upgrade]: https://cloudnative-pg.io/docs/1.28/installation_upgrade/
[support]: https://cloudnative-pg.io/docs/1.28/supported_releases/
[barman-install]: https://github.com/cloudnative-pg/plugin-barman-cloud/blob/v0.7.0/web/versioned_docs/version-0.7.0/installation.mdx
[barman-notes]: https://github.com/cloudnative-pg/plugin-barman-cloud/releases/tag/v0.7.0
[hibernate]: https://github.com/cloudnative-pg/cloudnative-pg/tree/v1.28.4/pkg/reconciler/hibernation
[old]: ../../kubernetes/infra/cloudnativepg/cnpg-1.27.0.yaml
[immich]: ../../kubernetes/apps/immich/base/db.yaml
[recovery]: cluster-recovery.md#phase-4--cnpg-database-recovery
[helper]: ../../scripts/cnpg-hibernate.sh
[shutdown]: homelab-shutdown-startup.md
