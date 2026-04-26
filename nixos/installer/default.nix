{ lib, modulesPath, pkgs, ... }: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Allow root SSH login so nixos-anywhere can connect and install
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Simple initial password so you can log in via Proxmox console if needed
  users.users.root = {
    initialHashedPassword = lib.mkForce "$2b$05$C.mHot1I8WLvtfUD2UPQd.QT/UjV5BFUBkUgA4mBFH2tuQW7Ne0fK";
  };

  # QEMU guest agent so Proxmox can report IP addresses and manage power state
  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    git
    parted
    vim
  ];
}
