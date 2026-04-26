proxmox_endpoint      = "https://pve01.home.lab:8006/"
proxmox_username      = "terraform@pve"
proxmox_password_file = "~/.config/sops-nix/secrets/pve-terraform-key"
proxmox_insecure      = false

# NixOS installer ISO in Proxmox storage.
# Build your own with: nix build .#packages.x86_64-linux.installer  (from nixos/)
# Then upload the resulting ISO to Proxmox and set the path below.
nixos_iso = "local:iso/nixos-installer.iso"

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
