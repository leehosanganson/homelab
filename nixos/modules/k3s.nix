{ config
, lib
, ...
}:
let
  cfg = config.homelab.k3s;
  isServer = cfg.role == "server";

  # These nodes join an existing cluster whose flannel backend must be validated on the
  # live cluster (kubectl get ds -n kube-system flannel -o yaml | grep backend, or check
  # /var/lib/rancher/k3s/server/manifests/k3s-kube-flannel.yml / --flannel-backend).
  # Opening both UDP ports works regardless of which backend is in use; narrow to a single
  # backend after confirming the live cluster's setting.
  flannelBackendPorts = lib.unique (lib.concatMap (backend:
    if backend == "vxlan" then [ 8472 ]
    else if backend == "wireguard-native" then [ 51820 ]
    else [ ]
  ) cfg.flannelBackend);

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

    # Flannel VXLAN/WireGuard overlay backends; opening both UDP ports lets the node join
    # regardless of which backend the existing cluster uses. Narrow after live validation.
    flannelBackend = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "vxlan" "wireguard-native" ]);
      default = [ "vxlan" "wireguard-native" ];
      description = "Flannel overlay backends to allow in the firewall.";
    };

    # When true, enables k3s' embedded distributed registry (Spegel); opens TCP 5001.
    embeddedRegistry = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable k3s embedded distributed registry (Spegel).";
    };

    # These nodes JOIN an already-initialized HA cluster so they leave it false.
    # Exists so the module can later INITIALIZE a fresh cluster during migration when replacing nodes.
    clusterInit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Initialize a new k3s cluster (server-only).";
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
      inherit (cfg) role serverAddr extraFlags clusterInit;
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
        ++ [ 10250 ] # kubelet port required by the metrics server (all nodes must be reachable)
        ++ (lib.optionals cfg.embeddedRegistry [ 5001 ]); # Spegel distributed registry
      allowedUDPPorts = flannelBackendPorts;
    };
  };
}
