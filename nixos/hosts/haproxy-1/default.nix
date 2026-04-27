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
    source = "${sops-secrets}/keys/haproxy";
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
