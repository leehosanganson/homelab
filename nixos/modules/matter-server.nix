{ config, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 5580 ];

  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;
    "net.netfilter.nf_conntrack_netlink.mtu" = 64;
  };

  services.matter-server.enable = true;
}
