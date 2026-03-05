{ sops-secrets, ... }: {
  imports = [
    ../../modules/haproxy.nix
  ];

  system.stateVersion = "25.11";

  # PVE
  networking = {
    hostName = "haproxy-1";
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.251";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
  };

  services.cloud-init = {
    enable = true;
    settings.ssh_deletekeys = false;
  };

  services.qemuGuest.enable = true;

  boot.loader.grub.device = "/dev/sda";

  proxmox.qemuConf = {
    cores = 2;
    memory = 4096;
    diskSize = 8192;
  };

  environment.etc."ssh/haproxy1_key" = {
    source = "${sops-secrets}/haproxy1_key";
    mode = "0600";
    user = "root";
    group = "root";
  };

  # secrets
  sops = {
    defaultSopsFile = "${sops-secrets}/secrets.yaml";
    age.sshKeyPaths = [
      "/etc/ssh/haproxy1_key"
    ];

    secrets = {
      "dns-provider-env" = {
        owner = "acme";
        group = "acme";
      };
    };
  };

  # user
  users.users.ansonlee = {
    isNormalUser = true;
    extraGroups = [ "wheel" "haproxy" ];
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
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
