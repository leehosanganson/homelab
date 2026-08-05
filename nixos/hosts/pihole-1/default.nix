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
    # Use the peer Pi-hole as the resolver, with a public fallback.
    nameservers = [ "192.168.1.133" "1.1.1.1" ];
  };
}
