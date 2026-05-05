{ config, lib, pkgs, ... }:

let
  opencodePkgs = with pkgs; [
    bash
    coreutils
    which
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
    shell = pkgs.bash;
    description = "opencode service user";
    hashedPassword = "!";

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb leehosanganson@gmail.com"
    ];
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

  # Declarative SSH setup for opencode user git operations.
  # Key separation is explicit:
  # - /etc/ssh/bootstrap-vm is reserved for sops bootstrap decryption.
  # - /etc/ssh/opencode-user(.pub) is dedicated to opencode git auth.
  systemd.services.opencode-git-ssh-setup = {
    description = "Install opencode git SSH key material";
    wantedBy = [ "multi-user.target" ];
    before = [ "opencode.service" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "opencode-git-ssh-setup" ''
                set -euo pipefail

                # Backward-compatible one-time migration from legacy generic key names.
                # Keep /etc/ssh/bootstrap-vm dedicated to sops bootstrap only.
                if [[ ! -f /etc/ssh/opencode-user && -f /etc/ssh/id_ed25519 ]]; then
                  install -m 0600 -o root -g root /etc/ssh/id_ed25519 /etc/ssh/opencode-user
                fi

                if [[ ! -f /etc/ssh/opencode-user.pub && -f /etc/ssh/id_ed25519.pub ]]; then
                  install -m 0644 -o root -g root /etc/ssh/id_ed25519.pub /etc/ssh/opencode-user.pub
                fi

                install -d -m 0700 -o opencode -g opencode /home/opencode/.ssh

                install -m 0600 -o opencode -g opencode /etc/ssh/opencode-user /home/opencode/.ssh/id_ed25519
                install -m 0644 -o opencode -g opencode /etc/ssh/opencode-user.pub /home/opencode/.ssh/id_ed25519.pub

                cat > /home/opencode/.ssh/config <<'EOF'
        Host github.com
          HostName github.com
          User git
          IdentityFile /home/opencode/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
        EOF

                chown opencode:opencode /home/opencode/.ssh/config
                chmod 0600 /home/opencode/.ssh/config

                touch /home/opencode/.ssh/known_hosts
                chown opencode:opencode /home/opencode/.ssh/known_hosts
                chmod 0644 /home/opencode/.ssh/known_hosts
      '';
    };
  };

  # Ensure ~/.config/sops-nix/secrets/ directory exists for sops-nix
  # to decrypt secrets into. Created early so sops-nix can write there.
  systemd.services.opencode-sops-dir = {
    description = "Create opencode user sops secrets directory";
    wantedBy = [ "multi-user.target" ];
    before = [ "opencode.service" ];
    after = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "opencode-sops-dir" ''
        set -euo pipefail
        install -d -m 0750 -o opencode -g opencode /home/opencode/.config/sops-nix/secrets
      '';
    };
  };

  # Service
  systemd.services.opencode = {
    description = "opencode headless server";
    wantedBy = [ "multi-user.target" ];
    requires = [ "opencode-git-ssh-setup.service" ];
    wants = [ "network-online.target" "opencode-sops-dir.service" ];
    after = [ "network-online.target" "opencode-git-ssh-setup.service" ];
    path = opencodePkgs;

    environment = {
      HOME = "/home/opencode";
      XDG_CACHE_HOME = "/var/cache/opencode";
      XDG_STATE_HOME = "/var/lib/opencode";
      XDG_RUNTIME_DIR = "/run/opencode";
      TMPDIR = "/tmp";
    };

    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/test -r ${config.sops.secrets."opencode-env".path}";
      # Intentionally force SHELL and PATH at launch to stabilize runtime even if EnvironmentFile has stale values.
      ExecStart = ''
        ${pkgs.coreutils}/bin/env SHELL=/run/current-system/sw/bin/bash PATH=/run/current-system/sw/bin:${lib.makeBinPath opencodePkgs} \
        ${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096
      '';
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
      ProtectSystem = "full";
      ReadWritePaths = [ "/home/opencode" "/var/lib/opencode" "/var/cache/opencode" "/run/opencode" ];
      PrivateTmp = true;
    };
  };
}
