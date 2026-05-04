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
    firewall.enable = true;
    firewall.allowedTCPPorts = [ 22 4096 ];
  };

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

      # Required for litellm
      "litellm-api-key" = {
        owner = "opencode";
        group = "opencode";
      };

      # Required for GitHub MCP
      "opencode-github-pat" = {
        owner = "opencode";
        group = "opencode";
      };

      # Required for kubectl
      "kube-config" = {
        owner = "opencode";
        group = "opencode";
        mode = "0400";
      };
    };
  };

  # user
  users.users = {
    ansonlee = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
      ];
    };

    root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
    ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  nix.settings.trusted-users = [ "root" "ansonlee" ];

  # services
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
}
