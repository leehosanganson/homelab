{ config
, lib
, ...
}:
let
  cfg = config.homelab.pihole;
in
{
  # Per-host subscribed blocklists. Pass from each host's default.nix so the two
  # resolvers can differ (e.g. pihole-1 blocks NSFW, pihole-2 doesn't).
  options.homelab.pihole.blocklists = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        url = lib.mkOption { type = lib.types.str; };
        type = lib.mkOption {
          type = lib.types.enum [ "allow" "block" ];
          default = "block";
        };
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
        description = lib.mkOption { type = lib.types.str; default = ""; };
      };
    });
    default = [ ];
    description = "Pi-hole adlists subscribed to for this host.";
  };

  options.homelab.pihole.subnetRoutes = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "LAN subnets to advertise to the tailnet via Tailscale.";
  };

  config = {
    # lockKernelModules blocks runtime autoload; load NAT modules so tailscale's
    # iptables-nft can create the nat POSTROUTING chain (ts-postrouting MASQUERADE).
    # Mirrors nixos/modules/k3s.nix.
    boot.kernelModules = lib.mkIf (cfg.subnetRoutes != [ ]) [
      "nf_nat"
      "nft_chain_nat"
      "xt_MASQUERADE"
      "ip_tables"
    ];

    # Admin password: injected at boot via sops-nix + FTL env override
    sops.secrets."pihole-secret" = {
      mode = "0400";
    };

    systemd.services.pihole-ftl = {
      serviceConfig.EnvironmentFile = [
        config.sops.secrets."pihole-secret".path
      ];
    };

    services.pihole-ftl = {
      enable = true;
      openFirewallDNS = true; # Opens 53 TCP/UDP
      openFirewallWebserver = true;

      settings = {
        dns = {
          upstreams = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          listeningMode = "ALL";
          # Local DNS records (shared "Local DNS" / custom.list).
          hosts = [
            "192.168.1.250 haproxy-1.home.lab"
            "192.168.1.151 k3s-ctrl-01.home.lab"
            "192.168.1.152 k3s-ctrl-02.home.lab"
            "192.168.1.153 k3s-ctrl-03.home.lab"
            "192.168.1.154 k3s-ctrl-04.home.lab"
            "192.168.1.131 k3s-gpu-01.home.lab"
            "192.168.1.156 k3s-work-01.home.lab"
            "192.168.1.157 k3s-work-02.home.lab"
            "192.168.1.240 mac-mini.home.lab"
            "192.168.1.197 nas1.home.lab"
            "192.168.1.132 pihole-1.home.lab"
            "192.168.1.133 pihole-2.home.lab"
            "192.168.1.193 pve01.home.lab"
            "192.168.1.143 pve02.home.lab"
            "192.168.1.168 pve03.home.lab"
            "192.168.1.194 pve04.home.lab"
          ];
        };
        # Local DNS rewrite: resolve the homelab domain and all its subdomains
        # to the HAProxy
        misc.dnsmasq_lines = [
          "local=/homelab.leehosanganson.dev/"
          "address=/homelab.leehosanganson.dev/192.168.1.250"
          "local-ttl=3600"
        ];
        webserver.api.cli_pw = true; # required so `lists` load on boot
      };

      lists = cfg.blocklists;
    };

    services.pihole-web = {
      enable = true;
      ports = [ "80" ];
    };

    services.tailscale = {
      enable = true;
      openFirewall = true; # UDP for WireGuard NAT traversal
      # Server mode enables IP forwarding so the host can route tailnet clients
      # to the advertised LAN subnets.
      useRoutingFeatures = if cfg.subnetRoutes != [ ] then "server" else "client";
      # Advertise the LAN subnets so tailnet clients can reach internal
      # services (e.g. *.homelab.leehosanganson.dev → HAProxy VIP) over the
      # tailnet. Routes must also be approved in the Tailscale admin console.
      extraSetFlags = lib.mkIf (cfg.subnetRoutes != [ ]) [
        "--advertise-routes=${builtins.concatStringsSep "," cfg.subnetRoutes}"
      ];
    };

    # Tailnet can reach Pi-hole directly (DNS 53 + admin UI 80).
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
  };
}
