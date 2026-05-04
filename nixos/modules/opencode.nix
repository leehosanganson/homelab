{ config, pkgs, ... }:

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
  environment.systemPackages = opencodePkgs;

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

  # Git config for opencode path/use case.
  programs.git = {
    enable = true;
    config = {
      core.safeDirectory = "/home/opencode";
    };
  };

  systemd.tmpfiles.rules = [
    "d /home/opencode/.config 0750 opencode opencode -"
    "d /home/opencode/repos 0750 opencode opencode -"
  ];

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
