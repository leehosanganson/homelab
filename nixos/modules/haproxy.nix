{ config, ... }:

let
  keepalivedPriority = {
    "haproxy-1" = 150;
    "haproxy-2" = 120;
    "haproxy-3" = 100;
  }.${config.networking.hostName} or 100;
  hostIp = (builtins.elemAt config.networking.interfaces.eth0.ipv4.addresses 0).address;
  # NOTE: For clusters with more than 3 HAProxy nodes, extend keepalivedPeerIps accordingly.
  keepalivedPeerIps = [ "192.168.1.251" "192.168.1.252" "192.168.1.253" ];
  keepalivedPeers = builtins.filter (ip: ip != hostIp) keepalivedPeerIps;
in {
  # ACME Wildcard for *.infra.leehosanganson.dev
  security.acme = {
    acceptTerms = true;
    maxConcurrentRenewals = 1;
    defaults = {
      email = "leehosanganson@gmail.com";
      server = "https://acme-v02.api.letsencrypt.org/directory";
    };
    certs."infra.leehosanganson.dev" = {
      domain = "*.infra.leehosanganson.dev";
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      environmentFile = config.sops.secrets."dns-provider-env".path;
      group = "haproxy";
      postRun = "systemctl reload haproxy";
    };
  };

  users.users.haproxy.extraGroups = [ "acme" ];

  services.keepalived = {
    enable = true;
    openFirewall = true;
    extraConfig = ''
      vrrp_script chk_haproxy {
          script "/run/current-system/sw/bin/systemctl is-active --quiet haproxy"
          interval 2
          fall 2
          rise 2
          weight -20
      }

      vrrp_instance VI_HAPROXY {
          state BACKUP
          interface eth0
          virtual_router_id 51
          priority ${toString keepalivedPriority}
          advert_int 1

          # NOTE: auth_pass is plaintext (VRRP unicast auth is not cryptographically strong).
          # It only guards against accidental misconfiguration; protect the subnet to mitigate.
          authentication {
              auth_type PASS
              auth_pass homelab-haproxy
          }

          unicast_src_ip ${hostIp}
          unicast_peer {
      ${builtins.concatStringsSep "\n" (builtins.map (ip: "        ${ip}") keepalivedPeers)}
          }

          virtual_ipaddress {
              192.168.1.250/24 dev eth0
          }

          track_script {
              chk_haproxy
          }
      }
    '';
  };

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
          bind 127.0.0.1:8443 ssl crt /var/lib/acme/infra.leehosanganson.dev/full.pem accept-proxy
          mode http
        
          acl is_nas hdr(host) -i nas-1.infra.leehosanganson.dev
          use_backend synology if is_nas

          acl is_pihole_1 hdr(host) -i pihole-1.infra.leehosanganson.dev
          use_backend pihole_1 if is_pihole_1

          acl is_pihole_2 hdr(host) -i pihole-2.infra.leehosanganson.dev
          use_backend pihole_2 if is_pihole_2

      frontend k3s_api
          bind *:6443
          mode tcp
          option tcplog
          default_backend k3s_api_backend

      # --- BACKENDS ---
      backend local_ssl_termination
          mode tcp
          server loopback 127.0.0.1:8443 send-proxy-v2

      backend synology
      mode http
      server nas-1 192.168.1.197:5000 check
        
      http-request set-header Host nas-1.infra.leehosanganson.dev
      http-request set-header X-Forwarded-Proto https
      http-request set-header X-Forwarded-For %[src]
      http-request set-header X-Real-IP %[src]
        
      http-response set-header Content-Security-Policy "frame-ancestors 'self'"

      backend pihole_1
          mode http
          server pi1 192.168.1.132:80 check

          http-request set-header Host pihole-1.infra.leehosanganson.dev
          http-request set-header X-Forwarded-Proto https
          http-request set-header X-Forwarded-For %[src]
          http-request set-header X-Real-IP %[src]

      backend pihole_2
          mode http
          server pi2 192.168.1.133:80 check

          http-request set-header Host pihole-2.infra.leehosanganson.dev
          http-request set-header X-Forwarded-Proto https
          http-request set-header X-Forwarded-For %[src]
          http-request set-header X-Real-IP %[src]

      backend k3s
          mode tcp
          balance roundrobin
          option tcp-check
          server ctrl-01 192.168.1.151:443 check
          server ctrl-02 192.168.1.152:443 check
          server ctrl-03 192.168.1.153:443 check

      backend k3s_api_backend
          mode tcp
          balance roundrobin
          option tcp-check
          # inter 5: probe every 5 seconds (reduces noise from flaky API servers)
          server ctrl-01 192.168.1.151:6443 check inter 5
          server ctrl-02 192.168.1.152:6443 check inter 5
          server ctrl-03 192.168.1.153:6443 check inter 5
    '';
  };
}
