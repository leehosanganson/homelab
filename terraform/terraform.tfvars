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
    node      = "pve02"
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
  # "opencode-1" = {
  #  node      = "pve01"
  #  vm_id     = 301
  #  cores     = 4
  #  memory    = 4096
  #  disk_size = 40
  #  datastore = "local-lvm"
  # }
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
        vlan_id = 30
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
    node      = "pve04"
    vm_id     = 102
    cores     = 2
    memory    = 2048
    disk_size = 20
    datastore = "local-lvm"
  }
  "pihole-2" = {
    node      = "pve02"
    vm_id     = 103
    cores     = 2
    memory    = 2048
    disk_size = 20
    datastore = "local-lvm"
  }
  # NixOS k3s nodes — first of the rollout replacing the existing Ubuntu k3s
  # cluster. Both on pve04 (192.168.1.194); ctrl-04 is the control plane,
  # work-01 the worker. Join via existing cluster token (sops: k3s-token).
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
}
