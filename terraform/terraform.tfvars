proxmox_endpoint       = "https://pve01.home.lab:8006/"
proxmox_api_token_file = "~/.config/sops-nix/secrets/pve-terraform-api-token"
proxmox_insecure       = true

pve_ssh_private_key_file = "~/.ssh/id_ed25519"

nixos_iso = "local:iso/nixos-minimal-26.11.20260802.6438090-x86_64-linux.iso"

nodes = {
  "haproxy-1" = {
    node      = "pve01"
    vm_id     = 201
    cores     = 2
    memory    = 2048
    disk_size = 20
    datastore = "local-lvm"
  }
  "haproxy-2" = {
    node      = "pve04"
    vm_id     = 202
    cores     = 2
    memory    = 2048
    disk_size = 20
    datastore = "local-lvm"
  }
  "haproxy-3" = {
    node      = "pve03"
    vm_id     = 203
    cores     = 2
    memory    = 2048
    disk_size = 20
    datastore = "local-lvm",
  }
  "matter-server" = {
    node      = "pve01"
    vm_id     = 302
    cores     = 1
    memory    = 2048
    disk_size = 15
    datastore = "local-lvm"
    additional_network_devices = [
      {
        bridge  = "vmbr0"
        model   = "virtio"
        vlan_id = 40
      },
    ]
  }
  "hermes-agent" = {
    node      = "pve01"
    vm_id     = 303
    cores     = 2
    memory    = 4096
    disk_size = 30
    datastore = "local-lvm"
  }
  "pihole-1" = {
    node      = "pve01"
    vm_id     = 102
    cores     = 2
    memory    = 2048
    disk_size = 20
    datastore = "local-lvm"
  }
  "pihole-2" = {
    node      = "pve04"
    vm_id     = 103
    cores     = 2
    memory    = 2048
    disk_size = 20
    datastore = "local-lvm"
  }
  "k3s-ctrl-01" = {
    node      = "pve01"
    vm_id     = 108
    cores     = 4
    memory    = 8192
    disk_size = 250
    datastore = "local-lvm"
  }
  "k3s-ctrl-02" = {
    node      = "pve02"
    vm_id     = 109
    cores     = 4
    memory    = 4096
    disk_size = 250
    datastore = "local-lvm"
  }
  "k3s-ctrl-04" = {
    node      = "pve04"
    vm_id     = 104
    cores     = 4
    memory    = 4096
    disk_size = 250
    datastore = "local-lvm"
  }
  "k3s-work-01" = {
    node      = "pve04"
    vm_id     = 105
    cores     = 8
    memory    = 8192
    disk_size = 250
    datastore = "local-lvm"
  }
  "k3s-work-02" = {
    node      = "pve04"
    vm_id     = 106
    cores     = 8
    memory    = 8192
    disk_size = 250
    datastore = "local-lvm"
  }
  "k3s-work-03" = {
    node      = "pve01"
    vm_id     = 107
    cores     = 8
    memory    = 8192
    disk_size = 250
    datastore = "local-lvm"
  }
  "k3s-work-04" = {
    node      = "pve02"
    vm_id     = 110
    cores     = 8
    memory    = 16384
    disk_size = 250
    datastore = "local-lvm"
  }
}
