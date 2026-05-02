{ sops-secrets, ... }: {
  imports = [
    ../../modules/opencode.nix
    ../../modules/disko.nix
  ];

  system.stateVersion = "26.05";

  networking = {
    hostName = "opencode-1";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.1.161";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.132" ];
  };

  services.qemuGuest.enable = true;

  environment.etc."ssh/opencode-1" = {
    source = "${sops-secrets}/keys/opencode-1";
    mode = "0600";
    user = "root";
    group = "root";
  };

  # Secrets — sops-nix decrypts at boot using the host SSH key.
  # The opencode-env secret must contain all env vars for the service:
  #   OPENCODE_SERVER_PASSWORD=...
  #   GITHUB_TOKEN=...
  #   (and any AI provider API keys, e.g. ANTHROPIC_API_KEY=...)
  sops = {
    defaultSopsFile = "${sops-secrets}/secrets.yaml";
    age.sshKeyPaths = [
      "/etc/ssh/opencode-1"
    ];

    secrets = {
      "opencode-env" = {
        owner = "opencode";
        group = "opencode";
      };

      "litellm-api-key" = {
        owner = "opencode";
        path = "/var/lib/opencode/.config/sops-nix/secrets/litellm-api-key";
      };

      "opencode-github-pat" = {
        owner = "opencode";
        path = "/var/lib/opencode/.config/sops-nix/secrets/opencode-github-pat";
      };
    };
  };

  # user
  users.users.ansonlee = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
  ];

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  nix.settings.trusted-users = [ "root" "ansonlee" ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };

  services.resolved = {
    enable = true;
    settings.Resolve.DNSSEC = "false";
  };

  # Firewall: SSH + opencode server port
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 4096 ];
}
