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
    hostName = "pihole-1";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.132";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    # Host OS resolver: public upstream (FTL serves the network, not this host).
    nameservers = [ "1.1.1.1" "9.9.9.9" ];
  };

  # secrets — sops-nix decrypts at boot using the shared bootstrap-vm SSH key.
  sops.defaultSopsFile = "${sops-secrets}/secrets.yaml";

  homelab.pihole.exitNode = true;

  homelab.pihole.blocklists = [
    {
      url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt";
      description = "hagezi pro";
    }
    {
      url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/popupads.txt";
      description = "hagezi popup ads";
    }
    {
      url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/fake.txt";
      description = "hagezi fakes";
    }
    {
      url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/nsfw.txt";
      description = "hagezi nsfw";
    }
  ];
}
