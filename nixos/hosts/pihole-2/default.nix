{ sops-secrets, ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/hardening.nix
    ../../modules/pihole.nix
    ../../modules/disko.nix
    ../../modules/sops-bootstrap.nix
  ];

  system.stateVersion = "26.05";

  networking = {
    hostName = "pihole-2";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.133";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    # Host OS resolver: public upstream (FTL serves the network, not this host).
    nameservers = [ "1.1.1.1" "9.9.9.9" ];
  };

  # pihole-2 subscribes to a smaller set than pihole-1 (per-host blocklists).
  homelab.pihole.blocklists = [
    {
      url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt";
      description = "hagezi pro";
    }
    {
      url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/popupads.txt";
      description = "hagezi popup ads";
    }
  ];
}
