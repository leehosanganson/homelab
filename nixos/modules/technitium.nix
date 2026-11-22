{ config, lib, pkgs, ... }:
let
  cfg = config.homelab.technitium;
  peerRules = lib.concatMapStringsSep "\n" (ip: ''
    iptables -w -A nixos-fw -i eth0 -s ${ip} -p tcp --dport 53443 -j nixos-fw-accept
  '') cfg.clusterPeerIPs;
  haproxyIPs = [ "192.168.1.251" "192.168.1.252" "192.168.1.253" ];
  adminProxyRules = lib.concatMapStringsSep "\n" (ip: ''
    iptables -w -A nixos-fw -i eth0 -s ${ip} -p tcp --dport 5380 -j nixos-fw-accept
  '') haproxyIPs;
  reconciler = ../scripts/technitium-reconcile.py;
  reconcileConfig = pkgs.writeText "technitium-reconcile.json" (builtins.toJSON {
    clusterDomain = cfg.clusterDomain;
    blockListUrls = cfg.blockListUrls;
    zones = cfg.zones;
  });
  reconcileService = "technitium-dns-reconcile";
in
{
  options.homelab.technitium = {
    clusterPeerIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "IPv4 addresses of Technitium cluster peers allowed to use its HTTPS service.";
    };

    clusterDomain = lib.mkOption {
      type = lib.types.str;
      default = "technitium-cluster.infra.leehosanganson.dev";
      description = "Expected, immutable identity of the manually initialized Technitium cluster.";
    };

    blockListUrls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt"
        "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/popupads.txt"
        "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/fake.txt"
        "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/nsfw.txt"
      ];
      description = "Desired Technitium blocking list URLs.";
    };

    zones = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf (lib.types.submodule {
        options = {
          domain = lib.mkOption {
            type = lib.types.str;
            description = "Fully qualified name of a desired A record.";
          };
          ipAddress = lib.mkOption {
            type = lib.types.str;
            description = "IPv4 address for the desired A record.";
          };
        };
      }));
      default = {
        "home.lab" = [
          { domain = "haproxy-1.home.lab"; ipAddress = "192.168.1.250"; }
          { domain = "k3s-ctrl-01.home.lab"; ipAddress = "192.168.1.151"; }
          { domain = "k3s-ctrl-02.home.lab"; ipAddress = "192.168.1.152"; }
          { domain = "k3s-ctrl-03.home.lab"; ipAddress = "192.168.1.153"; }
          { domain = "k3s-ctrl-04.home.lab"; ipAddress = "192.168.1.154"; }
          { domain = "k3s-gpu-01.home.lab"; ipAddress = "192.168.1.131"; }
          { domain = "k3s-work-01.home.lab"; ipAddress = "192.168.1.156"; }
          { domain = "k3s-work-02.home.lab"; ipAddress = "192.168.1.157"; }
          { domain = "k3s-work-03.home.lab"; ipAddress = "192.168.1.158"; }
          { domain = "k3s-work-04.home.lab"; ipAddress = "192.168.1.159"; }
          { domain = "mac-mini.home.lab"; ipAddress = "192.168.1.240"; }
          { domain = "nas1.home.lab"; ipAddress = "192.168.1.197"; }
          { domain = "pihole-1.home.lab"; ipAddress = "192.168.1.132"; }
          { domain = "pihole-2.home.lab"; ipAddress = "192.168.1.133"; }
          { domain = "pve01.home.lab"; ipAddress = "192.168.1.193"; }
          { domain = "pve02.home.lab"; ipAddress = "192.168.1.143"; }
          { domain = "pve03.home.lab"; ipAddress = "192.168.1.168"; }
          { domain = "pve04.home.lab"; ipAddress = "192.168.1.194"; }
        ];
        "homelab.leehosanganson.dev" = [
          { domain = "homelab.leehosanganson.dev"; ipAddress = "192.168.1.250"; }
          { domain = "*.homelab.leehosanganson.dev"; ipAddress = "192.168.1.250"; }
        ];
      };
      description = "Desired A records grouped by Technitium zone.";
    };

    reconciliation.enable = lib.mkEnableOption "Technitium DNS state reconciliation";
  };

  config = lib.mkMerge [
    {
      services.technitium-dns-server = {
        enable = true;
        # DNS is available to routed clients. Admin HTTP and cluster HTTPS are
        # limited to their configured source addresses below.
        openFirewall = false;
      };

      networking.firewall = {
        # Source-specific rules use NixOS's iptables firewall chain.
        backend = "iptables";
        extraCommands = ''
          iptables -w -A nixos-fw -i eth0 -p udp --dport 53 -j nixos-fw-accept
          iptables -w -A nixos-fw -i eth0 -p tcp --dport 53 -j nixos-fw-accept
          ${peerRules}
          ${adminProxyRules}
        '';
      };
    }
    (lib.mkIf cfg.reconciliation.enable {
      assertions = [
        {
          assertion = cfg.clusterDomain == "technitium-cluster.infra.leehosanganson.dev";
          message = "Reconciliation requires the approved cluster domain technitium-cluster.infra.leehosanganson.dev.";
        }
      ];

      sops.secrets."technitium-api-token" = {
        key = "technitium-api-token";
        mode = "0400";
      };

      systemd.services.${reconcileService} = {
        description = "Reconcile declarative DNS state on the Technitium cluster primary";
        after = [ "network-online.target" "technitium-dns-server.service" ];
        wants = [ "network-online.target" "technitium-dns-server.service" ];
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "10min";
          DynamicUser = true;
          LoadCredential = [
            "technitium-api-token:${config.sops.secrets."technitium-api-token".path}"
          ];
          ExecStart = "${pkgs.python3}/bin/python3 ${reconciler} --config-file ${reconcileConfig} --token-file %d/technitium-api-token";
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        };
      };

      systemd.timers.${reconcileService} = {
        description = "Retry Technitium DNS state reconciliation";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "5m";
          Unit = "${reconcileService}.service";
        };
      };
    })
  ];
}
