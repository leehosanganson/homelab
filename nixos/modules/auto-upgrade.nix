{ config, lib, ... }:

let
  flake = "github:leehosanganson/homelab/main?dir=nixos#${config.networking.hostName}";
in
{
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
