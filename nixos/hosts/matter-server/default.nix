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
    interfaces.mgmt0.ipv4.addresses = [
      {
        address = "192.168.1.162";
        prefixLength = 24;
      }
    ];
    # Apple Thread VLAN30 data path (secondary NIC, no default route)
    interfaces.thread0.ipv4.addresses = [
      {
        address = "192.168.30.162";
        prefixLength = 24;
      }
    ];
    defaultGateway = {
      address = "192.168.1.1";
      interface = "mgmt0";
    };
    nameservers = [ "192.168.1.132" ];
    firewall.enable = true;

    # IPv6 — static ULA address for stable local connectivity; Thread routes are learned via RA/RIO.
    interfaces.mgmt0.ipv6.addresses = [
      {
        address = "fd00:1:0:162::162";
        prefixLength = 64;
      }
    ];
    defaultGateway6 = {
      address = "fd00:1::1";
      interface = "mgmt0";
    };
  };

  systemd.network.links = {
    "10-mgmt0" = {
      matchConfig.MACAddress = "bc:24:11:6e:3e:c3";
      linkConfig.Name = "mgmt0";
    };
    "20-thread0" = {
      matchConfig.MACAddress = "bc:24:11:47:87:e9";
      linkConfig.Name = "thread0";
    };
  };

  services.qemuGuest.enable = true;

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
