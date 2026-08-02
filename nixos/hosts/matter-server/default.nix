{ ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/matter-server.nix
    ../../modules/disko.nix
  ];

  system.stateVersion = "26.05";

  networking = {
    hostName = "matter-server";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    nameservers = [ "192.168.1.132" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 ];
      checkReversePath = "loose";
    };
    interfaces = {
      eth0 = {
        ipv4.addresses = [
          {
            address = "192.168.1.162";
            prefixLength = 24;
          }
        ];
        ipv6.addresses = [
          {
            address = "fd00:1:0:162::162";
            prefixLength = 64;
          }
        ];
      };
    };

    defaultGateway = {
      address = "192.168.1.1";
      interface = "eth0";
    };

    defaultGateway6 = {
      address = "fd00:1::1";
      interface = "eth0";
    };
  };

  services.qemuGuest.enable = true;

  # ssh — bind to eth0 explicitly to prevent multi-homed ambiguity
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
    listenAddresses = [
      { addr = "192.168.1.162"; port = 22; }
    ];
  };

  services.resolved = {
    enable = true;
    settings.Resolve.DNSSEC = "false";
  };
}
