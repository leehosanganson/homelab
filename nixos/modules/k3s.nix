{ config
, lib
, ...
}:
let
  cfg = config.homelab.k3s;
  isServer = cfg.role == "server";

  # VERIFY the existing cluster's CNI before provisioning (the new nodes join an
  # existing cluster, so the CNI/overlay is fixed by the cluster):
  #   kubectl get ds -A | grep -Ei "flannel|cilium|calico"
  #   kubectl get pods -A -o wide | grep -Ei "flannel|cilium|calico"
  # - Flannel (k3s default) VXLAN       -> keep flannelBackend = [ "vxlan" ]                 (UDP 8472)
  # - Flannel wireguard-native          -> keep flannelBackend = [ "wireguard-native" ]      (UDP 51820)
  # - Cilium/Calico replacing Flannel   -> set flannelBackend = [ ] and open that CNI's ports
  #                                        via extraUdpPorts / extraTcpPorts
  #                                        (Cilium VXLAN = UDP 8472, GENEVE = UDP 6081)
  # - Direct routing / no overlay       -> no overlay UDP ports needed
  # Opening both Flannel backends is a safe default for a stock Flannel cluster, but you
  # can narrow it after confirming on the live cluster.
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

    extraTcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Extra TCP ports to open (e.g. ports required by a custom CNI overlay).";
    };

    extraUdpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Extra UDP ports to open (e.g. Cilium GENEVE 6081 or custom-CNI overlay ports).";
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
        ++ (lib.optionals cfg.embeddedRegistry [ 5001 ]) # Spegel distributed registry
        ++ cfg.extraTcpPorts;
      allowedUDPPorts = lib.unique (flannelBackendPorts ++ cfg.extraUdpPorts);
    };
  };
}
