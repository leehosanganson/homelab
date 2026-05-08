{ sops-secrets, ... }: {
  imports = [
    ../../modules/users.nix
    ../../modules/opencode.nix
    ../../modules/disko.nix
    ../../modules/sops-bootstrap.nix
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

  # secrets — sops-nix decrypts at boot using the shared bootstrap-vm SSH key.
  sops = {
    defaultSopsFile = "${sops-secrets}/secrets.yaml";

    secrets = {
      # Required for litellm
      "litellm-api-key" = {
        owner = "opencode";
        group = "opencode";
        path = "/home/opencode/.config/sops-nix/secrets/litellm-api-key";
      };

      # Required for GitHub MCP
      "opencode-github-pat" = {
        owner = "opencode";
        group = "opencode";
        path = "/home/opencode/.config/sops-nix/secrets/opencode-github-pat";
      };

      # Required for kubectl
      "kube-config" = {
        owner = "opencode";
        group = "opencode";
        mode = "0400";
        path = "/home/opencode/.kube/config";
      };
    };
  };

  # user
  users.users = {
    ansonlee = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb lhs-desktop"
      ];
    };
  };

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
