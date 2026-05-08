{ config, pkgs, ... }:

let
  opencodePkgs = with pkgs; [
    opencode
    zsh
    vim
    git
    gh
    ripgrep
    nodejs
    python3
    jq
    curl
    wget
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
    shell = pkgs.zsh;
    description = "opencode service user";
    packages = opencodePkgs;
    initialPassword = "opencode"; # Requires a change on first login

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOuRvc3yYsvjGSLlvtiSTGYx8YscOGAxuLoQEgP/llb lhs-desktop"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFLmxFZ+MJIFIMc/t3bY/EzbN6io/c2lZw1Ab9R68NJk mac-mini"
    ];
  };

  users.groups.opencode = { };

  systemd.tmpfiles.rules = [
    "d /home/opencode 0700 opencode opencode - -"

    # Lock down .ssh
    "d /home/opencode/.ssh 0700 opencode opencode - -"
    "f /home/opencode/.ssh/id_ed25519 0600 opencode opencode - -"
    "f /home/opencode/.ssh/id_ed25519.pub 0644 opencode opencode - -"
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

  programs.ssh = {
    extraConfig = ''
      Host github.com
        HostName github.com
        User git
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
        UserKnownHostsFile ~/.ssh/known_hosts
    '';
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Service
  services.envfs.enable = true;

  systemd.services.opencode = {
    description = "opencode headless server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = opencodePkgs;

    environment = {
      BASH_ENV = "/etc/bashrc";
      HOME = "/home/opencode";
      XDG_CONFIG_HOME = "/home/opencode/.config";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      TERM = "xterm-256color";
    };

    serviceConfig = {
      ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096";
      User = "opencode";
      Group = "opencode";
      RuntimeDirectory = "opencode";
      WorkingDirectory = "/home/opencode";

      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };
}
