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
    # Use the peer Pi-hole as the resolver, with a public fallback.
    nameservers = [ "192.168.1.132" "1.1.1.1" ];
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
