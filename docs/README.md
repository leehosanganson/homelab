# Documentation Index

## Infrastructure & Architecture

- [homelab-architecture/](homelab-architecture/) — Homelab architecture diagrams and images (`homelab-diagram.dot`, `homelab-diagram.svg`, `server-rack.jpg`)

### Diagram-as-Code Workflow

Architecture diagrams are authored as Graphviz `.dot` files and rendered to SVG. The pre-commit hook in `tools/hooks/pre-commit` automates this — install it once after cloning:

```bash
bash tools/install-hooks.sh
```

Then any staged `.dot` file is automatically re-rendered to SVG on commit. Requires `dot` (Graphviz) in your PATH — provided by `nix develop`.

## Runbooks

- [runbooks/cluster-recovery.md](runbooks/cluster-recovery.md) — Full-cluster recovery flow (Flux bootstrap, Velero restore, CNPG recovery)
- [runbooks/cluster-migration-k3s-to-talos.md](runbooks/cluster-migration-k3s-to-talos.md) — End-to-end migration flow from K3s to Talos (preflight, restore, cutover, rollback)
- [runbooks/workflows-testing-validation.md](runbooks/workflows-testing-validation.md) — Testing & Validation procedures for PR branches in-cluster via FluxCD
- [runbooks/iac-terraform-opentofu-provisioning.md](runbooks/iac-terraform-opentofu-provisioning.md) — Terraform/OpenTofu provisioning of NixOS VMs on Proxmox
- [runbooks/iac-nixos-configurations.md](runbooks/iac-nixos-configurations.md) — NixOS configurations, provisioning and rebuilding VMs
