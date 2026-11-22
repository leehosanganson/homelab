# Remote browser operations

The remote browser runs one persistent Kasm Chrome session at
[remote-browser.homelab.leehosanganson.dev](https://remote-browser.homelab.leehosanganson.dev).
KasmVNC streams the desktop to a web browser. Chrome starts at the Granblue
Fantasy URL. The browser profile uses the existing `chrome-runner-pvc` claim.
The Deployment keeps its existing Kubernetes object name, `chrome-runner`,
and its immutable selector, so GitOps updates it in place and its `Recreate`
strategy stops the old pod before starting the Kasm pod. The pod keeps the old
`app: chrome-runner` selector label for that transition; the service selects
`app.kubernetes.io/name: remote-browser`. Other resource identities use
`remote-browser`. The Deployment retains optional NVIDIA acceleration settings
(runtime class, GPU-node selector, toleration, and `/dev/dri` mount) without a
GPU resource request. Its existing CPU and memory requests and limits remain
unchanged.

## Before cutover: optional profile permission migration

**Do not start Kasm against the existing profile until a complete backup exists.**
Back up the PVC contents to a restorable location first. Do not run Selenium
Chrome and Kasm Chrome against the profile at the same time: Chrome profiles
are not safe for concurrent writers.

The optional permission Job is separate from the active application and
production Kustomize builds. Flux will not run it. It uses the old Selenium
image digest, which declares UID 1200. The old Deployment set `fsGroup: 1201`.
The Job runs as UID 1200/GID 1201. It validates that the mounted
`/home/seluser/.config` root is a directory, is not a symbolic link, and is
owned by UID 1200. It sets group ownership to 1201 and grants group read,
write, and execute access on that root and on profile directories; profile files
get group read and write access. These changes apply only to the root and the
`/home/seluser/.config/google-chrome` profile subtree; sibling entries under
`.config` are unchanged. Before changing permissions, the Job refuses symbolic
links, multiply-linked files, or entries not owned by UID 1200. It removes
world permissions from the changed paths and does not change ownership to UID
1000. The Kasm Deployment keeps
`fsGroup: 1201`, so Kasm UID 1000 can use that group access after the migration.

Follow these steps during a maintenance window:

1. Suspend the Flux `apps-production` Kustomization before applying the change.
   This pauses reconciliation for all production applications, not only this
   browser. Keep it suspended until the migration Job has succeeded and Kasm is
   ready to start:

   ```sh
   flux suspend kustomization apps-production --namespace flux-system
   ```

2. Suspending the Kustomization prevents future reconciliations, but does not
   cancel one that is already running. Wait for any in-progress reconciliation
   to finish before scaling; it may still apply changes while it runs. Read the
   Kustomization status every 10 seconds for up to 5 minutes:

   ```sh
   kubectl get kustomizations.kustomize.toolkit.fluxcd.io/apps-production \
     --namespace flux-system --output yaml
   ```

   Proceed only when `.spec.suspend` is `true`, top-level
   `.status.observedGeneration` matches `.metadata.generation`, a `Ready`
   condition has status `True`, and no `Reconciling` condition has status
   `True`. On this repository's Flux v2.8.5 / kustomize-controller v1.9.6,
   top-level `.status.observedGeneration` matching `.metadata.generation` is
   the positive signal that the queued suspend reconciliation was processed.
   Do not require the `Ready` condition's `observedGeneration` to match: it can
   remain stale after a suspended no-op reconciliation. Do not infer completion
   from `Reconciling=False` or from a missing `Reconciling` condition alone. If
   top-level `.status.observedGeneration` is stale, `Ready` is not `True`,
   `Reconciling=True` remains, or the 5-minute timeout hits, stop and
   investigate the conditions and events; do not scale the Deployment.

3. Scale `chrome-runner` to zero in namespace `remote-browser`. Wait for its
   pod to terminate, then confirm no Chrome process or other browser workload
   uses the PVC. Do not proceed while Chrome is running.

   ```sh
   kubectl scale deployment/chrome-runner --replicas=0 --namespace remote-browser
   kubectl get pods --namespace remote-browser --selector=app=chrome-runner
   ```

   Confirm the pod list is empty and verify no other workload has the PVC
   mounted before continuing.

4. Take and verify a restorable backup of the PVC contents. Inspect a restored
   copy first if you need to check profile behavior. Stop if the backup fails.
5. Apply the manual-only Job from the repository root:

   ```sh
   kubectl apply -k kubernetes/apps/remote-browser/manual-profile-migration
   kubectl wait --for=condition=complete job/remote-browser-profile-permissions \
     --namespace remote-browser --timeout=15m
   kubectl logs job/remote-browser-profile-permissions --namespace remote-browser
   kubectl describe job/remote-browser-profile-permissions --namespace remote-browser
   ```

   Require `Complete=True` and the success message in the logs. If the Job fails,
   inspect its logs and events; do not start Kasm. The Job is not safe to run
   while Chrome is using the profile. To retry a failed or completed Job, delete
   it and re-apply the manual Kustomize directory only after the failure is
   understood and the preconditions still hold.
6. After checking the Job result and confirming the profile remains backed up,
   resume Flux reconciliation. This allows the production Kasm Deployment to
   start. Verify Kasm can open the browser profile before normal use:

   ```sh
   flux resume kustomization apps-production --namespace flux-system
   ```

This Job is a permission migration only. It does not convert the Chrome profile
data format or preserve in-memory game state. The Job is not a live-profile test,
and no live-profile test was performed as part of this change. Exact profile
compatibility with Kasm still requires a test on a restored copy; a successful
permission Job does not prove that the profile or game session will work.

Store the KasmVNC password in the `remote-browser-kasm-password` key in the
configured Azure Key Vault before enabling the workload. The ExternalSecret
creates the Kubernetes secret consumed as `VNC_PW`. The browser login user is
`kasm_user`. Do not store the password in Git. The upstream container needs
writable runtime paths outside the profile, so its root filesystem is not
mounted read-only; it still runs as UID/GID 1000 with privilege escalation
blocked and all Linux capabilities dropped.

## Access and behavior

Use the Kasm login page through the HTTPS ingress. Keep this hostname behind a
private network boundary and retain Kasm authentication; private DNS by itself
does not prove that the service is private or protected from public routing.
The ingress terminates the repository's cert-manager TLS certificate and uses
HTTPS to the KasmVNC service. The backend transport skips certificate
verification because the upstream container uses its own self-signed
certificate. This tradeoff is limited to the in-cluster backend hop; it does
not validate the Kasm certificate. The ingress forwards `/` and all child
paths without rewrites to port 6901, which carries the Kasm UI and WebSocket
endpoint.
Traefik supports WebSocket upgrades through this same HTTPS service route.

KasmVNC allows the desktop to change resolution with the browser window, instead
of staying fixed to the old 1280-by-720 Selenium display. Clients cannot override
Kasm server settings, but desktop resize remains enabled and KasmVNC can still
process RFB `SetDesktopSize` requests. A disconnected browser does not stop the
persistent Kasm session. The no-user-session shutdown timeout and user idle
timeout are explicitly `never`. A pod restart still ends the session and starts
Chrome again from the persistent profile; in-memory session state is lost, and
downtime during restart is expected.

## Rollback

If startup, permissions, or profile behavior is wrong, stop the Kasm workload
before restoring or opening the profile with the old Selenium Chrome workload.
Restore the pre-cutover PVC backup if Kasm changed data or the profile is not
usable. Revert the Git change to restore the `chrome-runner` deployment and
route, then verify the restored profile before starting Selenium. Never run both
browser deployments at once.
