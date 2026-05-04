{ lib, sops-secrets, ... }: {
  # Deploy the shared SSH key so sops-nix can derive the age identity at boot.
  environment.etc."ssh/bootstrap-vm" = {
    source = "${sops-secrets}/keys/bootstrap-vm";
    mode = "0600";
    user = "root";
    group = "root";
  };

  # Point sops-nix to the shared key for age-based decryption.
  # We prepend so the shared key is tried first (deterministic order).
  sops.age.sshKeyPaths = lib.mkBefore [ "/etc/ssh/bootstrap-vm" ];
}
