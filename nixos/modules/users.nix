{ ... }: {
  users.users.ansonlee = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb lhs-desktop"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFLmxFZ+MJIFIMc/t3bY/EzbN6io/c2lZw1Ab9R68NJk mac-mini"
    ];
  };

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

  # Disable signature verification so local-to-remote rebuilds (rebuild.sh) work.
  # The default NixOS channel profile sets require-sigs=true, which blocks
  # nixos-rebuild --target-host because locally-built closures aren't signed.
  nix.settings.require-sigs = false;
}
