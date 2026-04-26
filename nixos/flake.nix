{
  description = "IaC with NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    sops-secrets = {
      url = "git+ssh://git@github.com/leehosanganson/sops.git?ref=main";
      flake = false;
    };
  };

  outputs = { nixpkgs, nixos-generators, disko, nixos-anywhere, sops-nix, sops-secrets, ... }@inputs: {
    # NixOS host configurations — deployed via nixos-anywhere (initial) or
    # nixos-rebuild switch --target-host (updates). See scripts/ for usage.
    nixosConfigurations.haproxy-1 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; inherit sops-secrets; };
      modules = [
        ./hosts/haproxy-1
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
      ];
    };

    nixosConfigurations.haproxy-2 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; inherit sops-secrets; };
      modules = [
        ./hosts/haproxy-2
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
      ];
    };

    # Minimal NixOS installer ISO for Proxmox VM templates.
    # Build: nix build .#packages.x86_64-linux.installer
    # Upload the resulting ISO to Proxmox, then use provision.sh to install.
    packages.x86_64-linux.installer = nixos-generators.nixosGenerate {
      system = "x86_64-linux";
      format = "iso";
      modules = [ ./installer ];
    };

    # Pinned nixos-anywhere — used by provision.sh via `nix run .#nixos-anywhere`
    # so the provisioning tool version is locked in flake.lock alongside everything else.
    apps.x86_64-linux.nixos-anywhere = nixos-anywhere.apps.x86_64-linux.nixos-anywhere;
  };
}
