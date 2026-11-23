# Remote browser operations

The remote browser runs one persistent Kasm Chrome session at
[remote-browser.homelab.leehosanganson.dev](https://remote-browser.homelab.leehosanganson.dev).
KasmVNC streams the desktop to a web browser. Chrome starts at the Granblue
Fantasy URL.

The one-time migration to Kasm is complete. The current Kasm home, including
its Chrome profile and later changes, is stored on `kasm-home-pvc`, which the
Kasm container mounts at `/home/kasm-user`. The bootstrap init container has
been removed. The Deployment does not seed or reseed this home automatically
from the image defaults or `chrome-runner-pvc`. The original
`chrome-runner-pvc` remains the older profile source and is not mounted by the
current Kasm runtime. A pre-migration backup or snapshot, if available and
verified, may restore only the older source profile; it cannot recover changes
made to the Kasm home after migration.
Kasm startup generates a self-signed certificate at
`${HOME}/.vnc/self.pem`. KasmVNC uses that same path for both its certificate
and key.

The Deployment keeps its existing Kubernetes object name, `chrome-runner`, and
immutable selector. GitOps updates it in place, and its `Recreate` strategy
stops the old pod before starting Kasm. The pod keeps the old `app:
chrome-runner` selector label for that transition; the service selects
`app.kubernetes.io/name: remote-browser`. Other resource identities use
`remote-browser`. The Deployment retains the NVIDIA runtime class, GPU-node
selector, toleration, and `/dev/dri` mount without a GPU resource request. CPU
and memory requests and limits remain unchanged.

## Current home and recovery

The populated `kasm-home-pvc` is the sole Kasm runtime home; Kasm mounts it at
`/home/kasm-user`. No init container or automatic seed/reseed exists. Preserve
this claim. Before replacing it, back up the active Kasm home and verify the
recovery plan. This runbook does not claim that a current Kasm-home backup
exists.

A pre-migration backup or snapshot, if available and verified, may restore only
the old Chrome profile; it cannot recover changes made in the Kasm home.

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

Reverting only this bootstrap-removal change restores the previous Kasm
Deployment, including its bootstrap initContainer; it does not return the service
to Selenium. The current `kasm-home-pvc`, its
`.kasm-home-bootstrap-complete` marker, and all Kasm home data remain untouched
by this cleanup reversion. The restored initContainer sees the existing marker
and leaves the home unchanged.

To return to Selenium, stop Kasm first, then separately roll back the original
Kasm migration to restore the Selenium Deployment and route using the original
`chrome-runner-pvc`. Never run Kasm and Selenium Chrome at the same time. The
original claim or its snapshot contains only the pre-migration Chrome state;
it does not contain Kasm changes made after migration.

`kasm-home-pvc` has the Flux annotation
`kustomize.toolkit.fluxcd.io/prune: disabled`. If rollback removes this PVC from
the applied manifests, Flux leaves the PVC in place rather than pruning it. If
the same claim is later added back to the manifests, Flux reconciles the
existing claim; check its current binding and data before changing its spec.
This PVC uses the repository's default StorageClass, `synology-default`, which
has `reclaimPolicy: Delete`. Manually deleting the PVC can therefore also
delete its backing volume and data. Keep the
claim until its contents are no longer needed and a verified backup or other
recovery plan exists. Do not manually delete this production PVC as a way to
reset, reseed, or roll back Kasm. Any future PVC lifecycle change requires a
separately reviewed recovery plan. The prune annotation does not prevent
intentional manual deletion.

A pre-migration backup or snapshot, if available and verified, may restore only
the original profile if it is damaged or you need it in a known state. It cannot
recover Kasm home data or changes made after migration.
