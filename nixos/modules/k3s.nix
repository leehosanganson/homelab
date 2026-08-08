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

    # k3s's containerd needs overlayfs, and flannel needs the vxlan CNI backend
    # plus the bridge/netfilter stack for kube-proxy. Load all at boot because
    # security.lockKernelModules (hardening module) disables runtime loading.
    boot.kernelModules = [
      "overlay"      # containerd overlayfs snapshotter
      "vxlan"        # flannel VXLAN CNI backend
      "veth"         # flannel CNI pod<->bridge veth pairs
      "bridge"       # CNI bridge
      "br_netfilter" # iptables/bridge filter for kube-proxy
      "nf_conntrack" # connection tracking
      "nf_nat"       # NAT for kube-proxy
      # netfilter/iptables extension modules the flannel CNI plugins need
      # (portmap/-m comment, MASQUERADE, addrtype, MARK).
      "xt_comment"    # CNI portmap plugin -m comment
      "xt_MASQUERADE" # pod<->external SNAT masquerade
      "xt_multiport"  # CNI portmap plugin -m multiport match
      "xt_statistic"  # kube-proxy -m statistic random (round-robin across multiple endpoints)
      "xt_addrtype"   # CNI addrtype rules
      "xt_mark"       # CNI MARK rules
      "nft_chain_nat" # registers nat table chains (PREROUTING/POSTROUTING) for iptables-nft/DNAT
      "xt_nat"        # DNAT/SNAT target for iptables-nft compat (CNI portmap)
      "ipt_REJECT"    # REJECT target (IPv4) used by kube-proxy KUBE rules (ClusterIP reachability)
      "ip6t_REJECT"   # REJECT target (IPv6) — token/parity module required if IPv6 is enabled
      "ip_tables"     # IPv4 rule infrastructure (legacy iptables compat for CNI)
      "ip6_tables"    # IPv6 rule infrastructure (legacy iptables compat for CNI)
    ];

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
        [ 22 ] # ssh (see hardening module)
        ++ [ 6443 ] # Kubernetes API server (server only; harmless on agents)
        ++ (lib.optionals isServer [ 2379 2380 ]) # etcd client/peer (server)
        ++ [ 10250 ]; # kubelet port required by the metrics server (all nodes must be reachable)
      allowedUDPPorts = [ 8472 ]; # Flannel VXLAN overlay (the existing cluster's CNI backend; k3s default)
    };
  };
}
