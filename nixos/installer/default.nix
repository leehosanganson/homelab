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

  users.users.root = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
    ];
  };

  # QEMU guest agent so Proxmox can report IP addresses and manage power state
  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    git
    parted
    vim
  ];
}
