{ modulesPath, pkgs, ... }: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Allow root SSH login so nixos-anywhere can connect and install
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Simple initial password so you can log in via Proxmox console if needed
  users.users.root.initialPassword = "nixos";

  # QEMU guest agent so Proxmox can report IP addresses and manage power state
  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    git
    parted
    vim
  ];
}
