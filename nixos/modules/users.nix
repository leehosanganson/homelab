{ config, pkgs, ... }: {
  # Root access for provisioning (SSH key-based)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb lhs-desktop"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFLmxFZ+MJIFIMc/t3bY/EzbN6io/c2lZw1Ab9R68NJk mac-mini"
  ];

  # Allow passwordless sudo for wheel group (required for nixos-rebuild --target-host)
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  # Trusted users for Nix operations
  nix.settings.trusted-users = [ "root" "ansonlee" ];
}
