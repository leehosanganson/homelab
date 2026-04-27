proxmox_endpoint       = "https://pve01.home.lab:8006/"
proxmox_api_token_file = "~/.config/sops-nix/secrets/pve-terraform-api-token"
proxmox_insecure       = true

nixos_iso = "local:iso/nixos-minimal-26.05.20260302.cf59864-x86_64-linux.iso"

nodes = {
  "haproxy-2" = {
    node      = "pve01"
    vm_id     = 202
    cores     = 1
    memory    = 2048
    disk_size = 20
    datastore = "local-lvm"
  }
}
