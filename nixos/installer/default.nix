{ lib, modulesPath, pkgs, ... }: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Allow root SSH login so nixos-anywhere can connect and install
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Empty password for console access during provisioning only.
  # WARNING: Only boot this ISO on a trusted network segment.
  users.users.root = {
    initialHashedPassword = lib.mkForce "";
  };

  # QEMU guest agent so Proxmox can report IP addresses and manage power state
  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    git
    parted
    vim
  ];
}
