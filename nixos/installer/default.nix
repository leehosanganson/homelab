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

  # Networking
  networking = {
    usePredictableInterfaceNames = false;
    nameservers = [ "192.168.1.132" ];
    defaultGateway = {
      address = "192.168.1.1";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fd00:1::1";
      interface = "eth0";
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 ];
      checkReversePath = "loose";
    };
  };

  environment.systemPackages = with pkgs; [
    git
    parted
    vim
  ];
}
