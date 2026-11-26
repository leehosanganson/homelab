# Temporary Traefik router inventory

This temporary diagnostic exposes only Traefik's `GET /api/rawdata` endpoint on the unexposed `traefik` entry point. The IngressRoute applies an IPAllowList for loopback addresses and has no Service, public entry point, or dashboard route. Keep the inventory local: it contains internal routing configuration. Do not paste it into chat, a PR, or logs.

The resources are in `kubernetes/infra/traefik/overlays/default/` and are marked `homelab.leehosanganson.dev/temporary: remove-after-mini-qr-verification`. Merge and reconcile their add-PR only for the approved verification window. Immediately after capturing the required per-replica snapshots, submit and reconcile a separate cleanup PR that removes both resources, their Kustomize entries, this runbook, and its docs index link. Verify the API route is absent from each replica and port-forwarded `/api/rawdata` returns 404. Do not leave this diagnostic enabled after the Mini QR verification.

## Read the inventory from each Traefik replica

1. Confirm the production Kubernetes context and list the Traefik pods:
   ```bash
   kubectl config current-context
   kubectl get nodes -o wide
   kubectl -n kube-system get pods \
     -l app.kubernetes.io/instance=traefik-kube-system,app.kubernetes.io/name=traefik \
     -o wide
   ```
   Set `CONTEXT` to the verified context name and use it in both terminals below.
2. Start a loopback-only port-forward to **one pod by name** (not the load-balanced Service):
   ```bash
   CONTEXT=production-context
   POD=traefik-pod-name
   kubectl --context "$CONTEXT" -n kube-system port-forward \
     --address 127.0.0.1 "pod/$POD" 18080:8080
   ```
3. In another terminal, fetch and validate the raw inventory. Keep this file local and delete it after inspection:
   ```bash
   set -euo pipefail
   CONTEXT=production-context
   umask 077
   inventory=$(mktemp)
   trap 'rm -f -- "$inventory"' EXIT
   curl --noproxy '*' --fail --silent --show-error --max-time 10 \
     http://127.0.0.1:18080/api/rawdata > "$inventory"
   jq -e '(.routers // {} | type == "object") and (.tcpRouters // {} | type == "object")' \
     "$inventory" >/dev/null
   jq -r '(.routers // {}) | to_entries[] |
     [.key, .value.rule, .value.service, ((.value.middlewares // []) | join(",")), .value.status] | @tsv' \
     "$inventory"
   jq -r '(.tcpRouters // {}) | to_entries[] |
     [.key, .value.rule, .value.service, .value.status] | @tsv' \
     "$inventory"
   rm -- "$inventory"
   trap - EXIT
   ```
4. Inspect all HTTP and TCP routers for the Mini QR host, wildcard/catch-all rules, and routes to `mini-qr` or the Authentik outpost. During route-off, require no router that can serve either backend for the Mini QR hostname. The diagnostic route itself is expected in the inventory. A Kubernetes manifest list or a TLS handshake failure alone is not proof.
5. Stop the port-forward after the inventory commands finish. If any command fails, the shell trap removes the local inventory file. Repeat for the other Traefik pod. Record only a pass/fail result and the pod names; do not retain or publish the raw JSON.

If the response is not valid JSON, the endpoint is unavailable, a replica is missing, or the IPAllowList denies the loopback request, stop and investigate. Do not widen the allowlist, expose port 8080 through a Service, enable insecure API access, or switch the route to `web`/`websecure` as a workaround.
