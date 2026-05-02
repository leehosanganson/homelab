{ config, pkgs, ... }:

let
  cfg = config.services.opencode;
in {
  # opencode: headless AI coding agent server
  #
  # Runs `opencode serve` as a systemd service. Secrets (server password,
  # GitHub token, and AI provider keys) are supplied via sops-nix and
  # injected as environment variables through EnvironmentFile.
  #
  # Port 4096 is exposed on all interfaces so that Traefik (running on the
  # K3s cluster) can reverse-proxy the service.

  environment.systemPackages = with pkgs; [
    # Runtime tools opencode needs to function as a coding agent
    opencode
    git
    ripgrep
    nodejs
    nodePackages.typescript-language-server
    python3
    jq
    curl
    wget
  ];

  users.users.opencode = {
    isSystemUser = true;
    group = "opencode";
    home = "/var/lib/opencode";
    createHome = true;
    description = "opencode service user";
  };

  users.groups.opencode = {};

  systemd.services.opencode = {
    description = "opencode headless server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      HOME = "/var/lib/opencode";
    };

    serviceConfig = {
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096";
      User = "opencode";
      Group = "opencode";
      WorkingDirectory = "/var/lib/opencode";

      # Inject secrets: OPENCODE_SERVER_PASSWORD, GITHUB_TOKEN, and AI provider keys
      EnvironmentFile = config.sops.secrets."opencode-env".path;

      # Restart policy
      Restart = "on-failure";
      RestartSec = "5s";

      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/opencode" ];
      PrivateTmp = true;
    };
  };

  networking.firewall.allowedTCPPorts = [ 4096 ];
}
