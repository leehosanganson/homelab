{ sops-secrets, ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/hardening.nix
    ../../modules/k3s.nix
    ../../modules/disko.nix
    ../../modules/sops-bootstrap.nix
  ];

  system.stateVersion = "26.05";

  networking = {
    hostName = "k3s-ctrl-04";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.154";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    # Host OS resolver: public upstream.
    nameservers = [ "192.168.1.133" "1.1.1.1" "9.9.9.9" ];
  };

  # secrets — sops-nix decrypts at boot using the shared bootstrap-vm SSH key.
  sops.defaultSopsFile = "${sops-secrets}/secrets.yaml";

  homelab.k3s = {
    enable = true;
    role = "server";
    serverAddr = "https://192.168.1.250:6443";
  };
}
