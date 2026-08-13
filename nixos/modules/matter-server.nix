_:

{
  # IPv6 settings for Thread Border Router support — required for Matter device discovery
  # NOTE: IPv6 forwarding MUST be disabled (0) for Thread reachability probing (RFC 4191).
  # Enabling it prevents proper network change detection and can cause up to 30-minute outages.
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 0;
    "net.ipv6.conf.default.forwarding" = 0;
    # Accept Router Advertisements so the kernel can learn Thread routes via RIO
    "net.ipv6.conf.all.accept_ra" = 1;
    "net.ipv6.conf.default.accept_ra" = 1;
    # Allow receipt of Route Information Options (RIO) from Thread Border Router
    "net.ipv6.conf.all.accept_ra_rt_info_max_plen" = 64;
    "net.ipv6.conf.default.accept_ra_rt_info_max_plen" = 64;
    # Enable kernel IPv6 route preference for Thread network selection
    "net.ipv6.conf.all.route_preferences" = 1;
    # Dual-NIC design: eth0 handles management/default route; eth1 is the Thread VLAN30 path.
    # Do NOT use RA-derived default routes on either NIC — rely on our static default gateway
    # while still accepting RA + RIO information globally.
    "net.ipv6.conf.eth0.accept_ra_defrtr" = 0;
    "net.ipv6.conf.eth1.accept_ra_defrtr" = 0;
  };

  # Ports & vlan 30
  networking = {
    useDHCP = false;

    firewall = {
      allowedUDPPorts = [ 5353 5540 ];
      allowedTCPPorts = [ 5540 5580 ];
    };

    interfaces.eth1.ipv4.addresses = [
      {
        address = "192.168.30.162";
        prefixLength = 24;
      }
    ];

    # Thread on-mesh prefix reached through the Thread Border Router on VLAN30 (eth1).
    # ETH1 has only link-local IPv6, so the next-hop is the border router's link-local
    # address on this segment (dev eth1). Static route makes Thread reachability durable —
    # it no longer depends on flaky RIO/RA renewal (no RAs are observed on eth1).
    interfaces.eth1.ipv6.routes = [
      {
        address = "fd60:6d9c:7edd::";
        prefixLength = 64;
        via = "fe80::80f:9c40:ee1e:a70b";
      }
    ];
  };

  # Avahi mDNS responder — required for Matter device discovery during commissioning
  services.avahi = {
    enable = true;
    reflector = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # matterjs-server (matter.js-based implementation)
  # Replaced python-matter-server which was archived and EOL.
  services.matterjs-server = {
    enable = true;
    listenAddress = "0.0.0.0";
    openFirewall = true;
    extraArgs = [ "--primary-interface=eth1" ];
  };
}
