# Remote browser operations

The remote browser runs one persistent Kasm Chrome session at
[remote-browser.homelab.leehosanganson.dev](https://remote-browser.homelab.leehosanganson.dev).
KasmVNC streams the desktop to a web browser. Chrome starts at the Granblue
Fantasy URL.

The original `chrome-runner-pvc` claim is a read-only migration source. Kasm
uses a separate `kasm-home-pvc` for its complete persistent home. On the first
start, a non-root init container copies the Kasm image's default home into the
new claim, then replaces `.config/google-chrome` with the old Chrome profile.
The init container runs as UID 1200/GID 1201. The Kasm container mounts the
complete new home at `/home/kasm-user`; the old claim is never mounted at
`~/.config` in the Kasm runtime. Kasm startup generates a self-signed
certificate at `${HOME}/.vnc/self.pem`. KasmVNC uses that same path for both its
certificate and key.

The Deployment keeps its existing Kubernetes object name, `chrome-runner`, and
immutable selector. GitOps updates it in place, and its `Recreate` strategy
stops the old pod before starting Kasm. The pod keeps the old `app:
chrome-runner` selector label for that transition; the service selects
`app.kubernetes.io/name: remote-browser`. Other resource identities use
`remote-browser`. The Deployment retains the NVIDIA runtime class, GPU-node
selector, toleration, and `/dev/dri` mount without a GPU resource request. CPU
and memory requests and limits remain unchanged.

## First start and migration safety

Take and verify a restorable backup of `chrome-runner-pvc` before migration.
Do not run Selenium Chrome and Kasm Chrome against the same profile at the same
time: Chrome profiles are not safe for concurrent writers.

Before cutover, inspect the root of `chrome-runner-pvc` through a read-only
inspection mount that does not request an `fsGroup`; for example, run
`stat -c '%u:%g %a' <source-pvc-root>` on that mount. Require UID:GID `0:1201`
and mode `2775`, the source-root values observed in this session. Stop if the
observed values differ; do not start Kasm until the mismatch is understood.
The pod sets `fsGroup: 1201` with `fsGroupChangePolicy: OnRootMismatch`. With
the expected root metadata, the policy is intended to avoid a recursive
group-ownership change. This is conditional on the root still matching: a
mismatch may cause kubelet to attempt recursive changes before the container
starts, and a read-only volume or mount alone does not prove kubelet skipped
them. The bootstrap itself only reads the source and mounts it read-only.

The bootstrap checks the new target before copying. An empty target is populated
from the image home and legacy Chrome profile. It applies group access so the
Kasm runtime (UID 1000/GID 1201) can use the copied files. Only after all copy
and permission steps succeed does it atomically write
`.kasm-home-bootstrap-complete`.

Bootstrap failure is fail-closed, but it is not generically safe to retry:

- If the completion marker is a regular, non-symlink file containing exactly
  `Bootstrapped from the image home and legacy Chrome profile.`, the init
  container exits without changing the target home. Kasm's later profile and
  home changes are preserved.
- If a marker path exists but is not a regular non-symlink file with that exact
  content, startup fails without changing the target home. Inspect the marker
  and target; do not delete or replace it to force another copy.
- If the target home is non-empty and has no marker, startup fails without
  changing it. Stop, inspect the target, and make a backup before deciding how
  to recover. Reset the new `kasm-home-pvc` only after confirming that it
  contains no needed Kasm data and Kasm has never started on it. Otherwise,
  recover the target manually. Do not reset or modify the original
  `chrome-runner-pvc`; preserve it as the migration source. Do not delete files
  or the marker just to force another copy.
- The old manual profile-permission Job has been removed and must not be used.

Keep the KasmVNC password in the `remote-browser-kasm-password` key in the
configured Azure Key Vault. The ExternalSecret creates the Kubernetes secret
consumed as `VNC_PW`. The browser login user is `kasm_user`. Do not store the
password in Git. The upstream container needs writable runtime paths, so its
root filesystem is not mounted read-only; it still runs as UID/GID 1000 with
privilege escalation blocked and all Linux capabilities dropped.

## Access and behavior

Use the Kasm login page through the HTTPS ingress. Keep this hostname behind a
private network boundary and retain Kasm authentication; private DNS by itself
does not prove that the service is private or protected from public routing.
The ingress terminates the repository's cert-manager TLS certificate and
routes to the KasmVNC Service. The Service carries Traefik's backend HTTPS
scheme and ServersTransport annotations; Traefik reads these backend settings
from Service metadata, not from the Ingress. The backend transport skips
certificate verification because the upstream container uses its own
self-signed certificate. This tradeoff is limited to the in-cluster backend
hop; it does not validate the Kasm certificate. The ingress forwards `/` and
all child paths without rewrites to port 6901, which carries the Kasm UI and
WebSocket endpoint. Traefik supports WebSocket upgrades through this same HTTPS service
route.

KasmVNC allows the desktop to change resolution with the browser window,
instead of staying fixed to the old 1280-by-720 Selenium display. Clients
cannot override Kasm server settings, but desktop resize remains enabled and
KasmVNC can still process RFB `SetDesktopSize` requests. A disconnected browser
does not stop the persistent Kasm session. The no-user-session shutdown timeout
and user idle timeout are explicitly `never`. A pod restart still ends the
session and starts Chrome from the persistent Kasm home; in-memory session
state is lost, and downtime during restart is expected.

## Rollback and PVC lifecycle

If startup or profile behavior is wrong, stop Kasm before starting Selenium.
Reverting the Git change restores the old `chrome-runner` Deployment and route,
which use the original `chrome-runner-pvc`. The separate Kasm home means writes
made by Kasm do not update the original profile. Kasm changes made after
migration are not included in that rollback. Never run both browser Deployments
at once.

`kasm-home-pvc` has the Flux annotation
`kustomize.toolkit.fluxcd.io/prune: disabled`. If rollback removes this PVC from
the applied manifests, Flux leaves the PVC in place rather than pruning it. If
the same claim is later added back to the manifests, Flux reconciles the
existing claim; check its current binding and data before changing its spec.
This PVC uses the repository's default StorageClass, `synology-default`, which
has `reclaimPolicy: Delete`. Manually deleting the PVC can therefore also
delete its backing volume and data. Keep the
claim until its contents are no longer needed and a verified backup or other
recovery plan exists. For intentional cleanup, first stop Kasm, inspect and
back up any needed data, then explicitly remove the PVC only after confirming
that deleting its backing volume is acceptable. The prune annotation does not
prevent intentional manual deletion.

Restore the pre-migration backup if the original profile is damaged or you
need it in a known state.
