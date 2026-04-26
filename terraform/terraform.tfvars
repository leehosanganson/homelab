proxmox_endpoint      = "https://pve01.home.lab:8006/"
proxmox_username      = "terraform@pve"
proxmox_password_file = "~/.config/sops-nix/secrets/pve-terraform-key"
proxmox_insecure      = false

nixos_iso = "local:iso/nixos-minimal-26.05.20260302.cf59864-x86_64-linux.iso"

nodes = {
  "haproxy-2" = {
    node      = "pve01"
    vm_id     = 901
    cores     = 2
    memory    = 4096
    disk_size = 20
    datastore = "local-lvm"
  }
}
