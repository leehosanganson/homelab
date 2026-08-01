{ sops-secrets, ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/hermes-agent.nix
    ../../modules/disko.nix
    ../../modules/sops-bootstrap.nix
  ];

  system.stateVersion = "26.05";

  # Let the interactive admin account share HERMES_HOME with the gateway
  # service so `hermes` over SSH works without switching users.
  users.users.ansonlee.extraGroups = [ "hermes" ];

  networking = {
    hostName = "hermes-agent";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.27";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.132" ];
  };

  services.qemuGuest.enable = true;

  sops = {
    defaultSopsFile = "${sops-secrets}/secrets.yaml";

    secrets = {
      "hermes-env" = {
        owner = "hermes";
        group = "hermes";
        # Let sops-nix use the default /run/secrets path; the Hermes NixOS
        # module activation script merges environmentFiles into .env, so the
        # secret file must not already be .env.
      };
      "kube-config" = {
        owner = "hermes";
        group = "hermes";
        mode = "0400";
        path = "/var/lib/hermes/.kube/config";
      };
    };
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };

  services.resolved = {
    enable = true;
    settings.Resolve.DNSSEC = "false";
  };

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
}