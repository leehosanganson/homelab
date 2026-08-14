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

  config = {
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
  };
}
