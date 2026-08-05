# Shared Pi-hole config for the DNS VMs (pihole-1/pihole-2).
# Per-host difference is only hostname + IP; web UI served on :80, fronted by HAProxy.
{
  config,
  ...
}: {
  services.pihole-ftl = {
    enable = true;
    openFirewallDNS = true;
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
          "192.168.1.240 mac-mini.home.lab"
          "192.168.1.197 nas1.home.lab"
          "192.168.1.132 pihole-1.home.lab"
          "192.168.1.133 pihole-2.home.lab"
          "192.168.1.193 pve01.home.lab"
          "192.168.1.143 pve02.home.lab"
          "192.168.1.168 pve03.home.lab"
        ];
      };
      webserver.api.cli_pw = true; # required so `lists` load on boot
    };

    # Subscribed blocklists (jsdelivr CDN mirrors of hagezi).
    lists = [
      {
        url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt";
        type = "block";
        description = "hagezi pro";
      }
      {
        url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/popupads.txt";
        type = "block";
        description = "hagezi popup ads";
      }
      {
        url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/fake.txt";
        type = "block";
        description = "hagezi fakes";
      }
      {
        url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/nsfw.txt";
        type = "block";
        description = "hagezi nsfw";
      }
    ];
  };

  services.pihole-web = {
    enable = true;
    ports = ["80"];
  };

  # Web/API password set on first boot via `pihole setpasswd`; not stored in repo.
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
