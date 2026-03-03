{ sops-secrets, ... }: {
  imports = [
    ../../modules/haproxy.nix
  ];

  system.stateVersion = "25.11";

  # PVE
  networking.hostName = "haproxy-1";
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings.ssh_deletekeys = false;
  };

  services.qemuGuest.enable = true;

  boot.loader.grub.device = "/dev/sda";

  virtualisation.diskSize = 8192;


  # secrets
  sops = {
    defaultSopsFile = "${sops-secrets}/secrets.yaml";
    age.sshKeyPaths = [
      "/etc/ssh/id_ed25519"
    ];

    secrets = {
      "dns-provider-env" = {
        owner = "acme";
        group = "acme";
      };
    };
  };

  # user
  users.users.ansonelee = {
    isNormalUser = true;
    extraGroups = [ "wheel" "haproxy" ];
    openssh.authorizedKeys.keys = [
      # Public Keys
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
    ];
  };

  # ssh
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };
}
