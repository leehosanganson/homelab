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

  outputs = { nixpkgs, sops-nix, sops-secrets, ... }@inputs: {
    nixosConfigurations.haproxy-1 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; inherit sops-secrets; };
      modules = [
        ./hosts/haproxy-vm
        sops-nix.nixosModules.sops
        "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
      ];
    };
  };
}
