{ sops-secrets, ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/matter-server.nix
    ../../modules/disko.nix
    ../../modules/sops-bootstrap.nix
  ];

  system.stateVersion = "26.05";

  networking = {
    hostName = "matter-server";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.254";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.132" ];
    firewall.enable = true;
  };

  services.qemuGuest.enable = true;

  # sops — no application secrets needed for Matter Server (self-contained)
  sops = {
    defaultSopsFile = "${sops-secrets}/secrets.yaml";
    secrets = { };
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
}
