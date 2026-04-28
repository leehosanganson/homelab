{ sops-secrets, ... }: {
  imports = [
    ../../modules/haproxy.nix
    ../../modules/disko.nix
  ];

  system.stateVersion = "25.11";

  networking = {
    hostName = "haproxy-1";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.251";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
  };

  services.qemuGuest.enable = true;

  environment.etc."ssh/haproxy-1" = {
    source = "${sops-secrets}/keys/haproxy-1";
    mode = "0600";
    user = "root";
    group = "root";
  };

  # secrets
  sops = {
    defaultSopsFile = "${sops-secrets}/secrets.yaml";
    age.sshKeyPaths = [
      "/etc/ssh/haproxy-1"
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

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
  ];

  security.sudo = {
    enable = true;
    # Intentional: passwordless sudo is required for nixos-rebuild --target-host,
    # which connects as root over SSH. The SSH key is the sole authentication factor.
    wheelNeedsPassword = false;
  };

  nix.settings.trusted-users = [ "root" "ansonlee" ];

  # ssh
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };

  services.resolved = {
    enable = true;
    settings.Resolve.DNSSEC = "false";
  };

  # Firewall
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
