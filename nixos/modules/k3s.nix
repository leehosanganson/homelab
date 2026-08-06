{ config
, lib
, ...
}:
let
  cfg = config.homelab.k3s;
  isServer = cfg.role == "server";
in
{
  options.homelab.k3s = {
    enable = lib.mkEnableOption "k3s node";

    role = lib.mkOption {
      type = lib.types.enum [ "server" "agent" ];
      description = "k3s node role: control-plane 'server' or 'agent' (worker).";
    };

    serverAddr = lib.mkOption {
      type = lib.types.str;
      description = "URL of an existing k3s server to join (e.g. https://192.168.1.250:6443).";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
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
      inherit (cfg) role serverAddr extraFlags;
      tokenFile = config.sops.secrets."k3s-token".path;
    };

    # Open the ports k3s uses between nodes.
    networking.firewall = {
      enable = true;
      allowedTCPPorts =
        [ ]
        ++ [ 22 ] # ssh (see hardening module)
        ++ [ 6443 ] # Kubernetes API server (server only; harmless on agents)
        ++ (lib.optionals isServer [ 2379 2380 ]) # etcd client/peer (server)
        ++ [ 10250 ]; # kubelet port required by the metrics server (all nodes must be reachable)
      allowedUDPPorts = [ 8472 ]; # Flannel VXLAN overlay (the existing cluster's CNI backend; k3s default)
    };
  };
}
