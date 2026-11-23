{ config, lib, ... }:

let
  flake = "github:leehosanganson/homelab/main?dir=nixos#${config.networking.hostName}";
in
{
  programs.ssh.knownHosts."github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  systemd.services.nixos-upgrade.environment.GIT_SSH_COMMAND =
    "/run/current-system/sw/bin/ssh -i /etc/ssh/bootstrap-vm -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/etc/ssh/ssh_known_hosts -o UserKnownHostsFile=/dev/null";

  system.autoUpgrade = {
    enable = true;
    inherit flake;
    upgrade = false;
    operation = "switch";
    allowReboot = false;
    dates = "hourly";
    randomizedDelaySec = "15m";

    # Nixpkgs builds this flag into a shell command without quoting its value.
    flags = lib.mkForce [
      "--refresh"
      "--flake ${lib.escapeShellArg flake}"
    ];
  };
}
