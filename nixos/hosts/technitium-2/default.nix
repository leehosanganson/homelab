{ sops-secrets, ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/hardening.nix
    ../../modules/technitium.nix
    ../../modules/disko.nix
    ../../modules/sops-bootstrap.nix
  ];

  system.stateVersion = "26.05";

  networking = {
    hostName = "technitium-2";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.212";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    nameservers = [ "1.1.1.1" "9.9.9.9" ];
  };

  sops.defaultSopsFile = "${sops-secrets}/secrets.yaml";

  homelab.technitium = {
    clusterPeerIPs = [ "192.168.1.211" ];
    clusterDomain = "technitium-cluster.infra.leehosanganson.dev";
    reconciliation.enable = true;
  };
}
