{
  description = "Homelab developer shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            terraform
            kubectl
            k9s
            kubernetes-helm
            kustomize
            fluxcd
            sops
            age
            git
            jq
            yq-go
            kubectl-neat
          ];

          shellHook = ''
            echo ""
            echo "🏠 Homelab Dev Shell"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Available tools:"
            echo "  terraform       — Infrastructure (Proxmox)"
            echo "  kubectl / k9s   — Kubernetes cluster interaction"
            echo "  helm            — Helm chart management"
            echo "  kustomize       — Kustomize overlay builds"
            echo "  flux            — FluxCD GitOps CLI"
            echo "  sops / age      — Secret management"
            echo "  jq / yq         — JSON/YAML processing"
            echo "  kubectl-neat    — Clean kubectl output"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
          '';
        };
      });
}
