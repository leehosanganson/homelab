{ modulesPath, pkgs, ... }: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Allow root SSH login so nixos-anywhere can connect and install
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Root access for provisioning (SSH key-based)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb lhs-desktop"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFLmxFZ+MJIFIMc/t3bY/EzbN6io/c2lZw1Ab9R68NJk mac-mini"
  ];

  # QEMU guest agent so Proxmox can report IP addresses and manage power state
  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    git
    parted
    vim
  ];
}
