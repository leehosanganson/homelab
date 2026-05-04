{ config, sops-secrets, pkgs, ... }:

let
  opencodePkgs = with pkgs; [
    git
    gh
    ripgrep
    nodejs
    nodePackages.typescript-language-server
    python3
    yq-go
    jq
    curl
    wget
    opencode
    kubectl
  ];
in

{
  users.users.opencode = {
    isNormalUser = true;
    group = "opencode";
    home = "/home/opencode";
    createHome = true;
    shell = pkgs.bashInteractive;
    description = "opencode service user";
    hashedPassword = "!";
  };

  users.groups.opencode = { };

  # Deploy SSH private key for git/gh authentication.
  environment.etc."home/opencode/.ssh/id_ed25519" = {
    source = "${sops-secrets}/keys/opencode-user";
    mode = "0600";
    user = "opencode";
    group = "opencode";
  };

  environment.etc."home/opencode/.ssh/id_ed25519.pub" = {
    source = "${sops-secrets}/keys/opencode-user.pub";
    mode = "0444";
    user = "opencode";
    group = "opencode";
  };

  # Dev Tools
  environment.systemPackages = opencodePkgs;

  # Git
  programs.git = {
    enable = true;
    config = {
      core.safeDirectory = "/home/opencode";
    };
  };

  # Service
  systemd.services.opencode = {
    description = "opencode headless server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = opencodePkgs;

    environment = {
      HOME = "/home/opencode";
      SHELL = "${pkgs.bashInteractive}/bin/bash";
    };

    serviceConfig = {
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096";
      User = "opencode";
      Group = "opencode";
      WorkingDirectory = "/home/opencode";

      EnvironmentFile = config.sops.secrets."opencode-env".path;

      Restart = "on-failure";
      RestartSec = "5s";

      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/home/opencode" ];
      PrivateTmp = true;
    };
  };
}
