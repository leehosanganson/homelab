{ config, pkgs, ... }:

{
  # opencode: headless AI coding agent server
  #
  # Runs `opencode serve` as a systemd service. Secrets (server password,
  # GitHub token, SSH key) are supplied via sops-nix.
  #
  # Port 4096 is exposed on all interfaces so that Traefik (running on the
  # K3s cluster) can reverse-proxy the service.

  environment.systemPackages = with pkgs; [
    opencode
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
    kubectl
  ];

  users.users.opencode = {
    isSystemUser = true;
    group = "opencode";
    home = "/var/lib/opencode";
    createHome = true;
    shell = pkgs.bashInteractive;
    description = "opencode service user";
    extraGroups = [ "kubernetes" ];
  };

  users.groups.opencode = { };

  # Git config for opencode path/use case.
  programs.git = {
    enable = true;
    config = {
      core.safeDirectory = "/var/lib/opencode";
      core.sshCommand = "${pkgs.openssh}/bin/ssh -F /etc/opencode/ssh/config";
      url."ssh://git@opencode-github/".insteadOf = "https://github.com/";
    };
  };

  # Service-scoped SSH config for opencode git operations.
  environment.etc."opencode/ssh/config" = {
    text = ''
      Host opencode-github github.com
        HostName github.com
        User git
        IdentityFile /etc/opencode/ssh/id_ed25519_github
        IdentitiesOnly yes
        UserKnownHostsFile /etc/opencode/ssh/known_hosts
    '';
    mode = "0444";
  };

  environment.etc."opencode/ssh/known_hosts" = {
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
    "d /var/lib/opencode/.config 0750 opencode opencode -"
    "d /var/lib/opencode/.config/opencode 0750 opencode opencode -"
    "d /var/lib/opencode/.config/ai 0750 opencode opencode -"
    "d /var/lib/opencode/repos 0750 opencode opencode -"
    "C /var/lib/opencode/.config/opencode/config.json 0640 opencode opencode - /etc/opencode/bootstrap/opencode-config.json"
    "C /var/lib/opencode/.config/ai/config.json 0640 opencode opencode - /etc/opencode/bootstrap/ai-config.json"
  ];

  # Kubernetes config — shared cluster access for all users on this VM.
  environment.variables.KUBECONFIG = "/etc/kube-config";

  systemd.services.opencode = {
    description = "opencode headless server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.git ];

    environment = {
      HOME = "/var/lib/opencode";
      SHELL = "${pkgs.bashInteractive}/bin/bash";
      GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -F /etc/opencode/ssh/config";
    };

    serviceConfig = {
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096";
      User = "opencode";
      Group = "opencode";
      WorkingDirectory = "/var/lib/opencode";

      EnvironmentFile = config.sops.secrets."opencode-env".path;

      Restart = "on-failure";
      RestartSec = "5s";

      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "tmpfs";
      ReadWritePaths = [ "/var/lib/opencode" ];
      PrivateTmp = true;
    };
  };
}
