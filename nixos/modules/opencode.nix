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

  # Dev Tools
  environment.systemPackages = opencodePkgs;

  # Git
  programs.git = {
    enable = true;
    config = {
      core.safeDirectory = "*";
    };
  };

  # Service
  systemd.services.opencode = {
    description = "opencode headless server";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = opencodePkgs;

    environment = {
      HOME = "/home/opencode";
      SHELL = "${pkgs.bashInteractive}/bin/bash";
      XDG_CACHE_HOME = "/var/cache/opencode";
      XDG_STATE_HOME = "/var/lib/opencode";
      XDG_RUNTIME_DIR = "/run/opencode";
      TMPDIR = "/tmp";
    };

    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/test -r ${config.sops.secrets."opencode-env".path}";
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096";
      User = "opencode";
      Group = "opencode";
      WorkingDirectory = "/home/opencode";

      EnvironmentFile = config.sops.secrets."opencode-env".path;

      Restart = "on-failure";
      RestartSec = "5s";

      RuntimeDirectory = "opencode";
      StateDirectory = "opencode";
      CacheDirectory = "opencode";

      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/home/opencode" "/var/lib/opencode" "/var/cache/opencode" "/run/opencode" ];
      PrivateTmp = true;
    };
  };
}
