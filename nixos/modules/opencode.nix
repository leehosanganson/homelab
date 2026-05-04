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
  # opencode: headless AI coding agent server
  #
  # Runs `opencode serve` as a systemd service. Secrets (server password,
  # GitHub token, SSH key) are supplied via sops-nix.
  #
  # Port 4096 is exposed on all interfaces so that Traefik (running on the
  # K3s cluster) can reverse-proxy the service.

  environment.systemPackages = opencodePkgs;

  users.users.opencode = {
    isSystemUser = false;
    group = "opencode";
    home = "/home/opencode";
    createHome = true;
    shell = pkgs.bashInteractive;
    description = "opencode service user";
    passwordHash = "disabled";
  };

  users.groups.opencode = { };

  # Git config for opencode path/use case.
  programs.git = {
    enable = true;
    config = {
      core.safeDirectory = "/home/opencode";
      core.sshCommand = "${pkgs.openssh}/bin/ssh -F /etc/opencode/ssh/config";
      url."ssh://git@github.com:".insteadOf = "https://github.com/";
    };
  };

  # Service-scoped SSH config for opencode git operations.
  environment.etc."opencode/ssh/config" = {
    text = ''
      Host github.com
        HostName github.com
        User git
        IdentityFile /etc/opencode/ssh/id_ed25519_github
        IdentitiesOnly yes
    '';
    mode = "0444";
  };

  environment.etc."ssh/known_hosts" = {
    text = ''
      github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
    '';
    mode = "0444";
  };

  # Declarative bootstrap for service config directories that were previously
  # populated out-of-band from dotfiles.
  environment.etc."opencode/bootstrap/opencode-config.json" = {
    text = ''
      {}
    '';
    mode = "0444";
  };

  environment.etc."opencode/bootstrap/ai-config.json" = {
    text = ''
      {}
    '';
    mode = "0444";
  };

  systemd.tmpfiles.rules = [
    "d /home/opencode/.config 0750 opencode opencode -"
    "d /home/opencode/.config/opencode 0750 opencode opencode -"
    "d /home/opencode/.config/ai 0750 opencode opencode -"
    "d /home/opencode/.kube 0700 opencode opencode -"
    "d /home/opencode/repos 0750 opencode opencode -"
    "C /home/opencode/.config/opencode/config.json 0640 opencode opencode - /etc/opencode/bootstrap/opencode-config.json"
    "C /home/opencode/.config/ai/config.json 0640 opencode opencode - /etc/opencode/bootstrap/ai-config.json"
  ];

  systemd.services.opencode = {
    description = "opencode headless server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = opencodePkgs;

    environment = {
      HOME = "/home/opencode";
      SHELL = "${pkgs.bashInteractive}/bin/bash";
      GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -F /etc/opencode/ssh/config";
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
      ProtectHome = "tmpfs";
      ReadWritePaths = [ "/home/opencode" ];
      PrivateTmp = true;
    };
  };
}
