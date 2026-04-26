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

## 4. Memory Management

The agent maintains persistent memory across sessions by categorizing user-shared information into typed Markdown documents stored under `docs/`.

### Buckets & File Locations

Information must be classified into exactly one of three buckets, each mapped to a dedicated file:

- **`user-preference`** → **`docs/user-preference.md`**: Stores personal preferences, stylistic choices, and behavioral expectations expressed by the user (e.g., preferred languages, formatting style, tool choices).
- **`project-context`** → **`docs/project-context.md`**: Stores facts about this repository and its environment that are unlikely to change often (e.g., cluster topology, external service dependencies, design decisions).
- **`workflow`** → **`docs/workflow.md`**: Stores recurring processes, step sequences, and procedural conventions the user follows (e.g., how to deploy, how to test, how to cut a release).

### File Lifecycle

- **Creating**: If the target `docs/<bucket>.md` file does not exist when a piece of information is to be stored, create it before writing.
- **Updating**: Append or merge new information into the appropriate file; do not duplicate entries that are already recorded.
- **Loading**: Before responding to any request where relevant context may be missing or ambiguous, read the applicable `docs/<bucket>.md` file(s) into memory.

### Recall Guarantee

- Never ask the user to repeat or re-explain anything that is already recorded in one of the three `docs/<bucket>.md` files.
- Cross-reference all three files when context spans multiple buckets.

## 5. Infrastructure as Code

NixOS VMs (e.g. `haproxy-1`) are provisioned and configured using a fully declarative, two-layer IaC approach.

### Layer 1 — VM Lifecycle (OpenTofu)

OpenTofu (`terraform/`) manages the virtual hardware boundary of each VM on Proxmox using the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) provider. It defines CPU, memory, disk size, and network — but intentionally avoids Cloud-Init or any OS-level configuration.

```bash
cd terraform
tofu init
tofu apply
```

### Layer 2 — OS & Configuration (NixOS + nixos-anywhere + disko)

Once OpenTofu creates the blank VMs, `nixos-anywhere` + `disko` remotely partitions the disk and installs NixOS from the flake in one step.

#### Build the installer ISO (one-time setup)

Build a minimal NixOS installer ISO, upload it to Proxmox storage, and reference it in `terraform.tfvars` as `nixos_iso`. OpenTofu will attach the ISO to new VMs so they boot into the installer.

```bash
cd nixos
nix build .#packages.x86_64-linux.installer
# result/iso/nixos-*.iso  →  upload to Proxmox
```

#### Initial provisioning

Boot the VM from the installer ISO (start it in Proxmox), then run:

```bash
./nixos/scripts/provision.sh haproxy-1 192.168.1.251
```

This calls `nix run .#nixos-anywhere -- --flake .#haproxy-1 root@192.168.1.251`, which uses disko to partition `/dev/sda` and installs the full NixOS configuration in one shot.

To inject pre-generated SSH host keys for sops-nix Day-0 secret decryption, place them under `nixos/scripts/keys/<hostname>/etc/ssh/` before running `provision.sh`.

#### Updating an existing host

```bash
./nixos/scripts/rebuild.sh haproxy-1 192.168.1.251
```

This runs `nixos-rebuild switch --flake .#haproxy-1 --target-host root@192.168.1.251 --build-host localhost`, building the new closure locally and activating it on the remote host over SSH.

To also pull the latest secrets revision before deploying, pass the optional flag:

```bash
./nixos/scripts/rebuild.sh --update-secrets haproxy-1 192.168.1.251
```

### Secrets (sops-nix)

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix). Each host expects a pre-generated SSH host key whose **public** key is registered as an age recipient in the sops-secrets repository. The corresponding **private** key is injected onto the host at provisioning time via `nixos-anywhere --extra-files` (stored locally in `./nixos/scripts/keys/<hostname>/etc/ssh/`, which is gitignored). On first boot, sops-nix uses the SSH host key to derive the age private key for decrypting secrets.
