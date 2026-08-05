# Shared Pi-hole configuration for the homelab DNS VMs (pihole-1, pihole-2).
#
# Both Pi-hole VMs are provisioned from this single module — the only
# differences between them (hostname + static IP) live in their own
# `nixos/hosts/<name>/default.nix`. Everything else is shared so the two
# resolvers stay in lock-step and either can replace the other.
#
# The web UI is served on port 80 inside the VM; external HTTPS access goes
# through HAProxy (`.infra.leehosanganson.dev`) which reverse-proxies to
# 192.168.1.132:80 / 192.168.1.133:80.
{
  config,
  lib,
  ...
}: let
  hostIp =
    (builtins.elemAt config.networking.interfaces.eth0.ipv4.addresses 0).address;
in {
  services.pihole-ftl = {
    enable = true;

    # The Pi-hole DNS server (UDP/TCP 53) is the whole point of these VMs.
    openFirewallDNS = true;
    # pihole-web binds 80 which HAProxy fronts. Keep the VM's own firewall open
    # for it so direct http://<ip>/admin also works for troubleshooting.
    openFirewallWebserver = true;

    settings = {
      # Upstream resolvers — change to taste. These are what Pi-hole forwards
      # non-blocked queries to.
      dns = {
        upstreams = [
          "1.1.1.1"
          "9.9.9.9"
        ];
        listeningMode = "ALL";
      };

      # Needed so the declarative `lists` below can be loaded via the API on boot.
      webserver.api.cli_pw = true;
    };

    # Declarative blocklists. On a fresh provision `pihole-ftl-setup` downloads
    # and loads these automatically. For migration, mirror the adlists from the
    # current VM — see docs/runbooks/pihole-vm-migration.md.
    lists = [
      {
        url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt";
        type = "block";
        enabled = true;
        description = "hagezi pro blocklist";
      }
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        type = "block";
        enabled = true;
        description = "StevenBlack hosts";
      }
    ];
  };

  services.pihole-web = {
    enable = true;
    ports = ["80"];
  };

  # Web UI admin password is NOT stored in the repo. Set it on first boot:
  #   pihole setpassword
  # (or push it via sops-nix if you want it managed declaratively).

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };

  services.resolved = {
    enable = true;
    settings.Resolve.DNSSEC = "false";
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22];
  };
}
