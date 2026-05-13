{ ... }: {
  services.matter-server.enable = true;

  networking.firewall.allowedTCPPorts = [ 5580 ];

  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.eth0.accept_ra_rt_info_max_plen" = 64;
  };
}
