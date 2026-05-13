{ sops-secrets, ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/matter-server.nix
    ./disko-config.nix
    ../../modules/sops-bootstrap.nix
  ];

  system.stateVersion = "26.05";

  networking = {
    hostName = "matter-server";
    useDHCP = true;
    usePredictableInterfaceNames = false;
    firewall.enable = true;
  };

  services = {
    openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      settings.PermitRootLogin = "prohibit-password";
    };

    qemuGuest.enable = true;

    resolved = {
      enable = true;
      settings.Resolve.DNSSEC = "false";
    };
  };

  sops.defaultSopsFile = "${sops-secrets}/secrets.yaml";
}
