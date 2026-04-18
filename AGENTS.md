## 1. Directory Structure & Hierarchical Patterns

The repository utilizes a layered approach to manage complexity across different levels of the stack.

### Kubernetes (Kustomize Pattern)

A strict `base/overlays` hierarchy is enforced for all Kubernetes resources:

- **`base/`**: Contains environment-agnostic manifests (Deployments, Services, etc.).
- **`overlays/`**: Manages environment-specific patches, secrets, and configurations (e.g., `default`, `staging`).

### Infrastructure vs. Applications

To maintain clear boundaries between system services and user services, the following structure is used:

- **`/kubernetes/infra`**: Foundational services required for cluster stability (e.g., `traefik`, `cert-manager`, `velero`).
- **`/kubernetes/apps`**: End-user services and applications (e.g., `immich`, `n8n`).

### VM Provisioning (Terraform Pattern)

Virtual machine lifecycle and hardware boundaries are managed via **Terraform** in the `/terraform` directory:

- Terraform defines CPU, memory, disk, and network for each Proxmox VM.
- OS-level configuration is **not** managed by Terraform — that is handled by NixOS.

### OS Management (NixOS Pattern)

Host-level configuration is managed via **Nix Flakes** in the `/nixos` directory:

- **`hosts/`**: Defines specific machine configurations.
- **`modules/`**: Contains reusable logic and configuration modules.
- **`scripts/provision.sh`**: Initial OS deployment via `nixos-anywhere` with `--extra-files` for SSH host key injection.
- **`scripts/rebuild.sh`**: Subsequent configuration updates via `nixos-rebuild switch --target-host`.

## 2. Naming Conventions

Consistency in naming ensures that the repository remains searchable and predictable.

- **Resources**: Kubernetes resources follow a `lowercase-kebab-case` convention (e.g., `actual-budget`).
- **Files**: File names are standardized based on their functional purpose (e.g., `deployment.yaml`, `ingress.yaml`, `kustomization.yaml`).
- **Directories**: Directory names match the service name or component type (e.g., `kubernetes/apps/immich`).
