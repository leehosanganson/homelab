_:

{
  networking.firewall.allowedTCPPorts = [ 5580 ];

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
    # Dual-NIC design: mgmt0 handles management/default route; thread0 is the Thread VLAN30 path.
    # Do NOT use RA-derived default routes on either NIC — rely on our static default gateway
    # while still accepting RA + RIO information globally.
    "net.ipv6.conf.mgmt0.accept_ra_defrtr" = 0;
    "net.ipv6.conf.thread0.accept_ra_defrtr" = 0;
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

  # Keep NetworkManager DNS integration enabled; this setting is known to work for this host.
  networking.networkmanager.dns = true;

  services.matter-server = {
    enable = true;
    extraArgs = { primary-interface = "thread0"; };
    # Force Matter CHIP stack to use thread0 (Apple Thread VLAN30 data path)
    # while mgmt0 remains the management/default-route interface.
  };
}
