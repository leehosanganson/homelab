{ ... }: {
  # Service
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "0.0.0.0" "::" ];
        port = 53;

        access-control = [
          "0.0.0.0/0 refuse"
          "::/0 refuse"
          "127.0.0.0/8 allow"
          "192.168.1.0/24 allow"
        ];

        hide-identity = true;
        hide-version = true;
        harden-glue = true;
        harden-dnssec-stripped = true;
        use-caps-for-id = true;
        edns-buffer-size = 1232;
        prefetch = true;
        num-threads = 2;
      };

      forward-zone = [
        {
          name = ".";
          forward-tls-upstream = true;
          forward-addr = [
            "1.1.1.1@853#cloudflare-dns.com"
            "1.0.0.1@853#cloudflare-dns.com"
            "8.8.8.8@853#dns.google"
            "8.8.4.4@853#dns.google"
          ];
        }
      ];
    };
  };
}
