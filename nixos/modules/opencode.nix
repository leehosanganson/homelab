{ config, pkgs, ... }:

let
  opencodePkgs = with pkgs; [
    bash
    coreutils
    which
    vim
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
    eza
  ];
in

{
  users.users.opencode = {
    isNormalUser = true;
    group = "opencode";
    extraGroups = [ "wheel" ];
    home = "/home/opencode";
    createHome = true;
    shell = pkgs.bash;
    description = "opencode service user";
    packages = opencodePkgs;
    initialPassword = "opencode"; # Requires a change on first login

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
    ];
  };

  users.groups.opencode = { };

  systemd.tmpfiles.rules = [
    "Z /home/opencode 0755 opencode opencode - -" # Recursive ownership for opencode
  ];

  # Git
  programs.git = {
    enable = true;
    config = {
      user = {
        name = "OpenCode@Homelab";
        email = "leehosanganson@gmail.com";
        signingkey = "~/.ssh/id_ed25519";
      };
      gpg.format = "ssh";
      commit.gpgsign = true;
    };
  };

  # Service
  services.envfs.enable = true;

  systemd.services.opencode = {
    description = "opencode headless server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = opencodePkgs;

    environment = {
      SHELL = "${pkgs.bash}/bin/bash";
      HOME = "/home/opencode";
      XDG_CONFIG_HOME = "/home/opencode/.config";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      TERM = "xterm-256color";
    };

    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/test -r ${config.sops.secrets."opencode-env".path}";
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096";
      User = "opencode";
      Group = "opencode";
      EnvironmentFile = config.sops.secrets."opencode-env".path;
      RuntimeDirectory = "opencode";
      WorkingDirectory = "/home/opencode";

      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };
}
