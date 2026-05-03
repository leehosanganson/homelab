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

  environment.etc."opencode/ssh/id_ed25519_github" = {
    source = "${sops-secrets}/keys/opencode-user";
    mode = "0400";
    user = "opencode";
    group = "opencode";
  };

  environment.etc."opencode/ssh/id_ed25519_github.pub" = {
    source = "${sops-secrets}/keys/opencode-user.pub";
    mode = "0444";
    user = "opencode";
    group = "opencode";
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

      "litellm-api-key" = {
        owner = "opencode";
        group = "opencode";
        path = "/var/lib/opencode/.config/sops-nix/secrets/litellm-api-key";
      };

      "opencode-github-pat" = {
        owner = "opencode";
        group = "opencode";
        path = "/var/lib/opencode/.config/sops-nix/secrets/opencode-github-pat";
      };

      "kube-config" = {
        owner = "root";
        group = "kubernetes";
        path = "/etc/kube-config";
      };
    };
  };

  # user
  users.groups.kubernetes = { };

  users.users.ansonlee = {
    isNormalUser = true;
    extraGroups = [ "wheel" "kubernetes" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
    ];
  };

  users.users.root = {
    extraGroups = [ "wheel" "kubernetes" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
    ];
  };

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

  services.qemuGuest.enable = true;

  services.resolved = {
    enable = true;
    settings.Resolve.DNSSEC = "false";
  };
}
