## 1. Directory Structure & Hierarchical Patterns

The repository utilizes a layered approach to manage complexity across different levels of the stack.

### Kubernetes (Kustomize Pattern)

A strict `base/overlays` hierarchy is enforced for all Kubernetes resources:

- **`base/`**: Contains environment-agnostic manifests (Deployments, Services, etc.).
- **`overlays/`**: Manages environment-specific patches, secrets, and configurations (e.g., `default`, `staging`).
- **`overlays/<env>/secrets.yaml`**: ExternalSecret manifests must be placed in the overlay directory (not `base/`), since they reference environment-specific secret stores and keys.

### Database Manifests

All database-related Kubernetes manifests (e.g., `deployment.yaml`, `service.yaml`, `pvc.yaml`) must be co-located under a `db/` subdirectory within the application's directory (e.g., `kubernetes/apps/immich/db/`), keeping database resources separate from the main application manifests.

### Infrastructure vs. Applications

To maintain clear boundaries between system services and user services, the following structure is used:

- **`/kubernetes/infra`**: Foundational services required for cluster stability (e.g., `traefik`, `cert-manager`, `velero`).
- **`/kubernetes/apps`**: End-user services and applications (e.g., `immich`, `n8n`).

### OS Management (NixOS Pattern)

Host-level configuration is managed via **Nix Flakes** in the `/nixos` directory:

- **`hosts/`**: Defines specific machine configurations.
- **`modules/`**: Contains reusable logic and configuration modules.

## 2. Naming Conventions

Consistency in naming ensures that the repository remains searchable and predictable.

- **Resources**: Kubernetes resources follow a `lowercase-kebab-case` convention (e.g., `actual-budget`).
- **Files**: File names are standardized based on their functional purpose (e.g., `deployment.yaml`, `ingress.yaml`, `kustomization.yaml`).
- **Directories**: Directory names match the service name or component type (e.g., `kubernetes/apps/immich`).

## 3. Kubernetes Best Practices

The following conventions apply to all Kubernetes workloads defined in this repository.

### ConfigMap for Environment Variables

Environment variables must never be defined inline under `env:` in the container spec of a Deployment manifest.

- **`configmap.yaml`**: Must be created in the `overlays/<env>/` directory (not `base/`) and referenced via `envFrom` or `env[].valueFrom.configMapKeyRef` in the Deployment.
- **Sensitive values** (passwords, tokens, API keys) remain in `secrets.yaml` under the overlay (via ExternalSecret); ConfigMaps are for non-sensitive configuration only.
- The ConfigMap resource must be listed in the overlay's `kustomization.yaml` `resources:` list.

### File-based ConfigMaps and Secrets

When a ConfigMap or Secret mounts a file (e.g. a JSON or YAML configuration file) rather than individual environment variables, the file content must not be inlined directly in the manifest YAML.

- **Separate source file**: The content must live as a standalone file in the overlay directory (e.g., `overlays/<env>/config.json`).
- **Kustomize generator**: The overlay's `kustomization.yaml` must use `configMapGenerator` (for non-sensitive files) or `secretGenerator` (for sensitive files) with a `files:` entry pointing to that source file, so Kustomize generates the manifest automatically.
- **No hand-authored data blocks**: Do not write a `data:` or `binaryData:` block by hand in `configmap.yaml` / `secret.yaml` for file-mounted content; let the generator produce it.
- **Naming**: The generator entry's `name:` must match the volume's `configMap.name` / `secret.secretName` reference in the Deployment. Use `generatorOptions.disableNameSuffixHash: true` in `kustomization.yaml` to prevent the auto-appended content hash from breaking fixed-name references.

### Security Context & Non-Root Execution

Containers must not run as root; a `securityContext` block is required on every container spec.

- **`runAsNonRoot: true`**: Must be set on all containers.
- **`runAsUser` / `runAsGroup`**: Should be set to a non-zero UID/GID appropriate for the image (e.g., `1000`).
- **`allowPrivilegeEscalation: false`**: Must be set on all containers.
- **`capabilities.drop: ["ALL"]`**: Must be set to remove all Linux capabilities by default; add back only the minimum required via `capabilities.add`.
- **`readOnlyRootFilesystem: true`**: Should be set where the application supports it; writable paths must be mounted explicitly via `volumeMounts`.

## 4. Infrastructure as Code

NixOS VMs are provisioned and configured using a fully declarative, two-layer IaC approach.

- **Layer 1 — VM Lifecycle (OpenTofu)**: OpenTofu manages VM hardware boundaries only (CPU, memory, disk, network). Cloud-Init and OS-level configuration are out of scope for this layer.
- **Layer 2 — OS & Configuration (NixOS)**: NixOS configuration lives in `nixos/`. All host provisioning and updates must go through `nixos-anywhere` + `disko`; never configure the OS manually.
- **Secrets**: SSH host keys for sops-nix must be pre-generated and placed under `nixos/scripts/keys/<hostname>/etc/ssh/` (gitignored) before provisioning.
- **Installer ISO**: The installer ISO must be built from the flake (`nix build .#packages.x86_64-linux.installer` in `nixos/`) and uploaded to Proxmox before running OpenTofu. The ISO path is referenced as `nixos_iso` in `terraform.tfvars`.

> For the full step-by-step operations guide, see [docs/iac-vm-provision.md](docs/iac-vm-provision.md) and [docs/iac-vm-configuration.md](docs/iac-vm-configuration.md).
