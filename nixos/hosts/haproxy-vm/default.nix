{ sops-secrets, ... }: {
  imports = [
    ../../modules/haproxy.nix
  ];

  networking.hostName = "haproxy-1";
  system.stateVersion = "25.11";

  # secrets
  sops = {
    defaultSopsFile = "${sops-secrets}/secrets.yaml";
    age.sshKeyPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
    ];

    secrets = {
      "dns-provider-env" = {
        owner = "acme";
        group = "haproxy";
      };
    };
  };

  # Allow secret-decryption key to be baked in but only if the file exists during build time
  sysmted.tmpfiles.rules = [
    "d /etc/ssh 0755 root root -"
  ];

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
  };

  # Proxmox VMA
  proxmox.qemuConf = {
    cores = 2;
    memory = 2048;
    net0 = "virtio,bridge=vmbr0"; # Change bridge if needed
    diskSize = 8192; # 8GB is plenty for HAProxy
  };
}
