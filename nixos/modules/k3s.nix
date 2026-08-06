# Shared k3s config for NixOS k3s nodes (control-plane server or worker agent).
#
# Per-host role + join endpoint are set via `homelab.k3s` in each host's
# default.nix. The cluster join token is injected at boot via sops-nix
# (`services.k3s.tokenFile`), never stored in the repo.
#
# This is the module that will eventually REPLACE the existing Ubuntu k3s nodes
# (ctrl-01/02/03, gpu-01) — same config, different `homelab.k3s.role`.
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.k3s;
  isServer = cfg.role == "server";
in {
  options.homelab.k3s = {
    enable = lib.mkEnableOption "k3s node";

    role = lib.mkOption {
      type = lib.types.enum ["server" "agent"];
      description = "k3s node role: control-plane 'server' or 'agent' (worker).";
    };

    # Where pre-existing control planes / the cluster is reachable for joins.
    # For the first control-plane this can point at an existing member; agents
    # should use the HAProxy API VIP (192.168.1.250:6443) or a control node.
    serverAddr = lib.mkOption {
      type = lib.types.str;
      description = "URL of an existing k3s server to join (e.g. https://192.168.1.250:6443).";
    };

    # The k3s agent/server join token, decrypted from sops at boot.
    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the k3s cluster token file (from sops-nix).";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra flags passed to the k3s binary.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."k3s-token" = {
      mode = "0400";
    };

    # k3s needs the cluster token for joins (server<->server and agent<->server).
    services.k3s = {
      enable = true;
      role = cfg.role;
      serverAddr = cfg.serverAddr;
      tokenFile = config.sops.secrets."k3s-token".path;
      extraFlags = cfg.extraFlags;
    };

    # Open the ports k3s uses between nodes.
    networking.firewall = {
      enable = true;
      allowedTCPPorts =
        [
          22 # ssh (see hardening module)
          6443 # Kubernetes API server (server only; harmless on agents)
        ]
        ++ (lib.optionals isServer [2379 2380]) # etcd client/peer (server)
        ++ [10250]; # kubelet
      allowedUDPPorts = [51820]; # WireGuard overlay (Flannel)
    };
  };
}
