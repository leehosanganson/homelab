# Shared hardening for NixOS VMs (kernel, network, and SSH/firewall baseline).
{ ... }: {
  # SSH — key-only auth, no passwords.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Basic host firewall; SSH allowed here, app ports added by services.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22];
  };

  security = {
    lockKernelModules = true;
    protectKernelImage = true;
    virtualisation.flushL1DataCache = "always";
  };

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 2;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
  };
}
