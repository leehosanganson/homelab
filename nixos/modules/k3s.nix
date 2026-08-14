{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.homelab.k3s;
  isServer = cfg.role == "server";

  # Wrapper for the Synology CSI node plugin's `chroot /host env iscsiadm ...`
  # invocations. synology-csi v1.2.1's parseSessions() does an unguarded
  # `strings.Split(e[3], ":")[1]` on each line of `iscsiadm -m session` output,
  # which panics with "index out of range [1] with length 1" whenever a line's
  # 4th whitespace field (the IQN position) contains no colon. On NixOS with
  # open-iscsi 2.1.12 a session can be caught mid-teardown (no IQN yet), so the
  # node plugin crash-loops, which also leaves the node without a stable volume
  # dataset (NodeStageVolume then fails with "Volume[..] is not found"). Filtering
  # `-m session` output to well-formed lines (4th field has a colon => an IQN)
  # prevents the panic while preserving every legitimate session line.
  iscsiadmWrapper = pkgs.writeShellScriptBin "iscsiadm" ''
    real="${config.services.openiscsi.package}/bin/iscsiadm"
    gawk="${pkgs.gawk}/bin/awk"
    if [ "''${1:-}" = "-m" ] && [ "''${2:-}" = "session" ]; then
      # CombinedOutput() merges stderr; normalise like the driver does and drop
      # any line the parser would choke on, while preserving the real exit code.
      "$real" "$@" 2>&1 | "$gawk" 'NF < 4 || $4 ~ /:/'
      exit "''${PIPESTATUS[0]}"
    fi
    exec "$real" "$@"
  '';
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
      "overlay" # containerd overlayfs snapshotter
      "vxlan" # flannel VXLAN CNI backend
      "veth" # flannel CNI pod<->bridge veth pairs
      "bridge" # CNI bridge
      "br_netfilter" # iptables/bridge filter for kube-proxy
      "nf_conntrack" # connection tracking
      "nf_nat" # NAT for kube-proxy
      # netfilter/iptables extension modules the flannel CNI plugins need
      # (portmap/-m comment, MASQUERADE, addrtype, MARK).
      "xt_comment" # CNI portmap plugin -m comment
      "xt_MASQUERADE" # pod<->external SNAT masquerade
      "xt_multiport" # CNI portmap plugin -m multiport match
      "xt_statistic" # kube-proxy -m statistic random (round-robin across multiple endpoints)
      "xt_addrtype" # CNI addrtype rules
      "xt_mark" # CNI MARK rules
      "nft_chain_nat" # registers nat table chains (PREROUTING/POSTROUTING) for iptables-nft/DNAT
      "xt_nat" # DNAT/SNAT target for iptables-nft compat (CNI portmap)
      "ipt_REJECT" # REJECT target (IPv4) used by kube-proxy KUBE rules (ClusterIP reachability)
      "ip6t_REJECT" # REJECT target (IPv6) — token/parity module required if IPv6 is enabled
      "ip_tables" # IPv4 rule infrastructure (legacy iptables compat for CNI)
      "ip6_tables" # IPv6 rule infrastructure (legacy iptables compat for CNI)
      # NFS client modules for the csi-nfs driver (mounts happen from the host
      # kernel; runtime module loading is locked by hardening).
      "nfs"
      "nfsv4"
      # Filesystem modules for CSI-provisioned volumes (Synology CSI volumes
      # are formatted ext4/btrfs/xfs; ext4 is already loaded for the rootfs).
      "btrfs"
      "xfs"
      # btrfs checksums need crc32c via the crypto API at mount time; runtime
      # module loading is locked by hardening, so it must load at boot.
      "crc32c_cryptoapi"
    ];

    # k3s needs the cluster token for joins (server<->server and agent<->server).
    services.k3s = {
      enable = true;
      inherit (cfg) role serverAddr extraFlags;
      disable = lib.optionals isServer [
        # Will be managed by FluxCD
        "metrics-server"
        "traefik"
      ];
      tokenFile = config.sops.secrets."k3s-token".path;
    };

    # kubelet mounts in-tree NFS PVs (spec.nfs) by running `mount -t nfs` on the
    # host, and util-linux resolves the type-specific helper (mount.nfs) from the
    # k3s unit's PATH. Upstream defaults the k3s unit PATH to only the (usually
    # unset) zfs package, so the FHS sbin dirs where tmpfiles places mount.nfs
    # (/sbin, /usr/sbin) are omitted and the helper is never found. The systemd
    # `path` option appends `/bin` and `/sbin` to each entry, so the entries "/"
    # and "/usr" here resolve to /bin:/sbin and /usr/bin:/usr/sbin respectively,
    # injecting exactly those helper directories into the unit's
    # Environment=PATH=.... Because this changes the unit's Environment=PATH=...,
    # a later `nixos-rebuild switch` restarts k3s, so the fix activates without
    # a manual `systemctl restart k3s`.
    systemd.services.k3s.path = [
      "/"
      "/usr"
    ];

    # Synology CSI (iSCSI) attaches need a host-side iscsid + config. The
    # nixpkgs openiscsi module also pulls "iscsi_tcp" into boot.kernelModules
    # (required at boot since hardening locks runtime module loading).
    services.openiscsi = {
      enable = true;
      name = "iqn.2026-08.com.homelab.k3s:${config.networking.hostName}";
    };

    # In-tree NFS PVs (spec.nfs, e.g. media-pv / qbit-download) are mounted by
    # kubelet on the host, which needs the userspace NFS mount helper + client
    # daemons (idmapd/statd) for NFSv4. Without them, kubelet's mount fails with
    # "fsconfig() failed: NFS: mount program didn't pass remote address." (exit 32).
    # In this nixpkgs snapshot, NFS *client* support is enabled by declaring nfs /
    # nfs4 as supported filesystems: the tasks/filesystems/nfs module then adds
    # nfs-utils to system.fsPackages and starts rpcbind/idmapd/statd. (The older
    # services.nfs.client option no longer exists here.) kubelet already reaches
    # mount(8) (the failure is at the helper stage), so the tmpfiles rules below
    # symlink util-linux's type-specific mount helpers (mount.nfs/mount.nfs4) into
    # /sbin and /usr/sbin. For kubelet to find them, the k3s unit's PATH must also
    # include those FHS directories — see the systemd.services.k3s.path override
    # above.
    boot.supportedFilesystems = [ "nfs" "nfs4" ];

    # The synology-csi node plugin runs `chroot /host env iscsiadm ...`; env
    # resolves via a FHS PATH (e.g. /usr/sbin, /sbin), which doesn't exist on
    # NixOS. Expose the wrapped iscsiadm there via symlinks into the Nix store.
    # mount.nfs is exposed the same way for kubelet's in-tree NFS mounts.
    systemd.tmpfiles.rules = [
      "L+ /usr/sbin/iscsiadm - - - - ${iscsiadmWrapper}/bin/iscsiadm"
      "L+ /sbin/iscsiadm - - - - ${iscsiadmWrapper}/bin/iscsiadm"
      "L+ /sbin/mount.nfs - - - - ${pkgs.nfs-utils}/bin/mount.nfs"
      "L+ /sbin/mount.nfs4 - - - - ${pkgs.nfs-utils}/bin/mount.nfs"
      "L+ /usr/sbin/mount.nfs - - - - ${pkgs.nfs-utils}/bin/mount.nfs"
      "L+ /usr/sbin/mount.nfs4 - - - - ${pkgs.nfs-utils}/bin/mount.nfs"
    ];

    # Resolve the NAS hostname from /etc/hosts so host-level processes (e.g. the
    # synology-csi node plugin, which reads resolv.conf directly and bypasses the
    # nscd/nsncd cache) don't flood the local DNS resolver. Keep this in sync
    # with the dns.hosts entry in modules/pihole.nix if the NAS IP ever changes.
    networking.hosts = {
      "192.168.1.197" = [ "nas1.home.lab" ];
    };

    # Open the ports k3s uses between nodes.
    networking.firewall = {
      enable = true;
      allowedTCPPorts =
        [ 22 ] # ssh (see hardening module)
        ++ [ 6443 ] # Kubernetes API server (server only; harmless on agents)
        ++ (lib.optionals isServer [ 2379 2380 ]) # etcd client/peer (server)
        ++ [ 10250 ] # kubelet port required by the metrics server (all nodes must be reachable)
        ++ [ 9100 ]; # node-exporter: Prometheus host scrape (hostNetwork)
      allowedUDPPorts = [ 8472 ]; # Flannel VXLAN overlay (the existing cluster's CNI backend; k3s default)
    };
  };
}
