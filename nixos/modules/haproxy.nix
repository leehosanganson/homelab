{ config, ... }: {
  # ACME Wildcard for *.home.leehosanganson.dev
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@leehosanganson.dev";
    certs."home.leehosanganson.dev" = {
      domain = "*.home.leehosanganson.dev";
      dnsProvider = "cloudflare";
      credentialsFile = config.sops.secrets."dns-provider-env".path;
      group = "haproxy";
      extraLegoFlags = [ "--dns-provider-env" ];
    };
  };

  users.users.haproxy.extraGroups = [ "acme" ];

  # Service
  services.haproxy = {
    enable = true;
    config = ''
      global
          log /dev/log local0
          stats socket /run/haproxy/admin.sock mode 660 level admin
          user haproxy
          group haproxy

          # See: https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate
          ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
          ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
          ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

      defaults
          log global
          mode http
          option httplog
          timeout connect 5000ms
          timeout client 50000ms
          timeout server 50000ms

      # --- FRONTENDS ---

      # Entry point for everything internal
      frontend tls_front
          bind *:443 ssl crt /var/lib/acme/home.leehosanganson.dev/full.pem
          
          # Routing Logic
          acl is_k3s_internal hdr(host) -m end .internal.leehosanganson.dev
          use_backend k3s_cluster if is_k3s_internal

          acl is_nas hdr(host) -i nas1.home.leehosanganson.dev
          use_backend synology if is_nas

          acl is_pihole_1 hdr(host) -i pihole-1.home.leehosanganson.dev
          use_backend pihole_1 if is_pihole_1

          acl is_pihole_2 hdr(host) -i pihole-2.home.leehosanganson.dev
          use_backend pihole_2 if is_pihole_2


      # --- BACKENDS ---

      backend synology
          server nas1 192.168.1.30:5000 check

      backend pihole_1
          server pi1 192.168.1.132:80 check

      backend pihole_2
          server pi2 192.168.1.133:80 check

      backend k3s
          mode tcp
          balance roundrobin
          option tcp-check
          server ctrl-01 192.168.1.151:443 check
          server ctrl-02 192.168.1.152:443 check
          server ctrl-03 192.168.1.153:443 check
    '';
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
