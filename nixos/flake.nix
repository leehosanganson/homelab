{
  description = "IaC with NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    sops-secrets = {
      url = "git+ssh://git@github.com/leehosanganson/sops.git?ref=main";
      flake = false;
    };
  };

  outputs = { nixpkgs, disko, sops-nix, sops-secrets, ... }@inputs: {
    nixosConfigurations.haproxy-1 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; inherit sops-secrets; };
      modules = [
        ./hosts/haproxy-1
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
      ];
    };
  };
}
