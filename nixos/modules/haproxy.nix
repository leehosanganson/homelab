{ config, ... }: {
  # ACME Wildcard for *.home.leehosanganson.dev
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "leehosanganson@gmail.com";
      server = "https://acme-v02.api.letsencrypt.org/directory";
      validMinDays = 999;
    };
    certs."home.leehosanganson.dev" = {
      domain = "*.home.leehosanganson.dev";
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets."dns-provider-env".path;
      group = "haproxy";
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
          ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets
          ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384

      defaults
          log global
          timeout connect 5000ms
          timeout client 50000ms
          timeout server 50000ms

      # --- FRONTENDS ---
      frontend main_gateway
          bind *:443
          mode tcp
          option tcplog

          # Inspect the SNI (Server Name Indication)
          tcp-request inspect-delay 5s
          tcp-request content accept if { req_ssl_hello_type 1 }

          # ACL for K3s (Passthrough)
          acl is_k3s_internal req_ssl_sni -m end .homelab.leehosanganson.dev
          use_backend k3s if is_k3s_internal

          # Default: Send everything else to local SSL termination
          default_backend local_ssl_termination 

      frontend tls_front
          bind 127.0.0.1:8443 ssl crt /var/lib/acme/home.leehosanganson.dev/full.pem accept-proxy
          mode http
        
          acl is_nas hdr(host) -i nas1.home.leehosanganson.dev
          use_backend synology if is_nas

          acl is_pihole_1 hdr(host) -i pihole-1.home.leehosanganson.dev
          use_backend pihole_1 if is_pihole_1

          acl is_pihole_2 hdr(host) -i pihole-2.home.leehosanganson.dev
          use_backend pihole_2 if is_pihole_2

      # --- BACKENDS ---
      backend local_ssl_termination
          mode tcp
          server loopback 127.0.0.1:8443 send-proxy-v2

      backend synology
          mode http
          server nas1 192.168.1.30:5000 check

      backend pihole_1
          mode http
          server pi1 192.168.1.132:80 check

      backend pihole_2
          mode http
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
}
