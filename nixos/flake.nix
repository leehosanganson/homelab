{
  description = "IaC with NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    sops-secrets = {
      url = "git+ssh://git@github.com/leehosanganson/sops.git?ref=main";
      flake = false;
    };
  };

  outputs = { nixpkgs, nixos-generators, sops-nix, sops-secrets, ... }: {
    # Build Proxmox VM image
    packages.x86_64-linux.haproxy-vma = nixos-generators.nixosGenerate {
      system = "x86_64-linux";
      format = "proxmox";
      modules = [
        sops-secrets.nixosModules.sops
        ./hosts/haproxy-vm/default.nix
        {
          _module.args.secrets = sops-secrets;
        }
      ];
    };

    # Enable `nixos-rebuild`
    nixosConfigurations.haproxy = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/haproxy-vm/default.nix
        sops-nix.nixosModules.sops
      ];
      specialArgs = {
        inherit sops-secrets;
      };
    };
  };
}
