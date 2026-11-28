{ sops-secrets, ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/hermes-agent.nix
    ../../modules/auto-upgrade.nix
    ../../modules/disko.nix
    ../../modules/sops-bootstrap.nix
  ];

  system.stateVersion = "26.05";

  # Let the interactive admin account share HERMES_HOME with the gateway
  # service so `hermes` over SSH works without switching users.
  users.users.ansonlee.extraGroups = [ "hermes" ];

  # The cron/skill system writes executable scripts under ~/.hermes/scripts.
  # Ensure it is created with the right ownership so the gateway service can
  # write cron scripts and the interactive user can inspect them.
  systemd.tmpfiles.rules = [
    "d /var/lib/hermes/.hermes/scripts 2770 hermes hermes - -"
  ];

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

  networking.interfaces.eth0.ipv4.routes = [
    { address = "10.42.0.0"; prefixLength = 24; via = "192.168.1.158"; }
    { address = "10.42.1.0"; prefixLength = 24; via = "192.168.1.159"; }
    { address = "10.42.2.0"; prefixLength = 24; via = "192.168.1.131"; }
    { address = "10.42.3.0"; prefixLength = 24; via = "192.168.1.154"; }
    { address = "10.42.4.0"; prefixLength = 24; via = "192.168.1.152"; }
    { address = "10.42.5.0"; prefixLength = 24; via = "192.168.1.151"; }
    { address = "10.42.6.0"; prefixLength = 24; via = "192.168.1.157"; }
    { address = "10.42.7.0"; prefixLength = 24; via = "192.168.1.156"; }
  ];

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.extraCommands = ''
    for cidr in 10.42.0.0/16; do
      iptables -w -A nixos-fw -i eth0 -s "$cidr" -p tcp --dport 8644 -j nixos-fw-accept
    done
  '';
}