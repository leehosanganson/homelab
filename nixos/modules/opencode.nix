{ config, pkgs, ... }:

{
  # opencode: headless AI coding agent server
  #
  # Runs `opencode serve` as a systemd service. Secrets (server password,
  # GitHub token, and AI provider keys) are supplied via sops-nix and
  # injected as environment variables through EnvironmentFile.
  #
  # Port 4096 is exposed on all interfaces so that Traefik (running on the
  # K3s cluster) can reverse-proxy the service.
  #
  # Config files (~/.config/opencode and ~/.config/ai) are sourced from
  # https://github.com/leehosanganson/dotfiles, cloned/pulled on every
  # nixos-rebuild switch so changes to the dotfiles repo are immediately
  # reflected without re-provisioning the host.

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

  # Clone/pull dotfiles repo and symlink config dirs on every activation.
  # Symlinks (not copies) are used so that a `git pull` in the dotfiles
  # directory instantly reflects changes — no rebuild required.
  system.activationScripts.opencodeDotfiles = {
    deps = [ "users" ];
    text = ''
      GIT="${pkgs.git}/bin/git"
      su -s /bin/sh opencode -c "
        DOTFILES_DIR=/var/lib/opencode/dotfiles

        # Clone if not present, otherwise pull latest
        if [ ! -d \"\$DOTFILES_DIR/.git\" ]; then
          $GIT clone https://github.com/leehosanganson/dotfiles \"\$DOTFILES_DIR\"
        else
          $GIT -C \"\$DOTFILES_DIR\" pull --ff-only
        fi

        # Ensure .config parent exists
        mkdir -p /var/lib/opencode/.config

        # Symlink opencode config dir
        rm -f /var/lib/opencode/.config/opencode
        ln -sf \"\$DOTFILES_DIR/opencode/.config/opencode\" /var/lib/opencode/.config/opencode

        # Symlink ai config dir
        rm -f /var/lib/opencode/.config/ai
        ln -sf \"\$DOTFILES_DIR/ai/.config/ai\" /var/lib/opencode/.config/ai
      "
    '';
  };

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
}
