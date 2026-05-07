{ lib, ... }: {
  # The bootstrap key is injected during provisioning at
  # /etc/ssh/bootstrap-vm from nixos/scripts/keys/<hostname>/etc/ssh.
  # Point sops-nix directly at that host-local injected path.
  sops.age.sshKeyPaths = lib.mkBefore [ "/etc/ssh/bootstrap-vm" ];
}
