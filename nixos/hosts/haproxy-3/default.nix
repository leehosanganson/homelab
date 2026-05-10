{ sops-secrets, ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/haproxy.nix
    ../../modules/disko.nix
    ../../modules/sops-bootstrap.nix
  ];

  system.stateVersion = "26.05";

  networking = {
    hostName = "haproxy-3";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.253";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
  };

  services.qemuGuest.enable = true;

  # secrets — sops-nix decrypts at boot using the shared bootstrap-vm SSH key.
  sops = {
    defaultSopsFile = "${sops-secrets}/secrets.yaml";

    secrets = {
      "dns-provider-env" = {
        owner = "acme";
        group = "acme";
      };
    };
  };

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
  networking.firewall.allowedTCPPorts = [ 22 80 443 6443 ];
}
