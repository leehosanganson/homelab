{ ... }: {
  imports = [
    ../../modules/unbound.nix
  ];

  system.stateVersion = "25.11";

  # PVE
  networking = {
    hostName = "unbound-1";
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.253";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    nameservers = [ "127.0.0.1" ];
  };

  services.cloud-init = {
    enable = true;
    settings.ssh_deletekeys = false;
  };

  services.qemuGuest.enable = true;

  boot.loader.grub.device = "/dev/sda";

  proxmox.qemuConf = {
    cores = 1;
    memory = 512;
    diskSize = 4096;
  };

  # user
  users.users.ansonlee = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # Public Keys
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
    ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  # ssh
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };

  # Firewall
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
