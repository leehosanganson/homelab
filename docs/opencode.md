# OpenCode Remote Server (Container Deployment)

This homelab deploys OpenCode as a Kubernetes workload (container deployment), exposed internally via Traefik ingress.

## Security comparison: VM vs Container

### Container on Kubernetes (chosen)

- **Pros**
  - Fast patching/rollbacks through GitOps and image updates.
  - Native network policy, ingress, and secret management integration.
  - Easier backup and portability with PVC + declarative manifests.
  - Lower resource overhead than one VM per service.
- **Risks and mitigations**
  - Shared kernel risk -> mitigated with non-root container, dropped Linux capabilities, RuntimeDefault seccomp, namespace isolation, and ingress/TLS.

### Dedicated VM

- **Pros**
  - Stronger kernel-level isolation boundary.
  - Useful for highly untrusted workloads or strict tenant isolation.
- **Tradeoffs**
  - Higher resource overhead.
  - More operational work (patching OS + runtime separately).
  - Slower iteration versus declarative Kubernetes deployments.

Given this homelab's existing Kubernetes-first operations model, container deployment gives the best balance of security and maintainability.

## Step-by-step implementation plan

1. **Create app manifests** under `kubernetes/apps/opencode/base` for Deployment, Service, Ingress, and PVC.
2. **Harden runtime security** in Deployment (`runAsNonRoot`, non-zero UID/GID, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, RuntimeDefault seccomp).
3. **Move configuration to overlay** (`kubernetes/apps/opencode/overlays/default/config.yaml`) and reference it via `envFrom`.
4. **Store secrets in ExternalSecret** (`kubernetes/apps/opencode/overlays/default/secrets.yaml`) for `OPENCODE_SERVER_PASSWORD` and `GITHUB_TOKEN` from Azure Key Vault.
5. **Expose service internally** via ingress host `opencode.homelab.leehosanganson.dev` with cert-manager-managed TLS.
6. **Wire into production overlay** by adding `../../opencode/overlays/default` to `kubernetes/apps/overlays/production/kustomization.yaml`.
7. **Create namespace** resource `kubernetes/apps/overlays/production/namespaces/opencode.yaml` and include it in the namespace kustomization.
8. **Validate manifests** with:
   - `kustomize build kubernetes/apps/opencode/overlays/default`
   - `kustomize build kubernetes/apps/overlays/production`
9. **Apply via existing GitOps flow** so Flux reconciles OpenCode automatically.

## Operations notes

- Create these Key Vault entries before reconciliation:
  - `opencode-server-password`
  - `opencode-github-token`
- OpenCode workspace data is persisted in `opencode-pvc` mounted at `/home/opencode/workspace`.
