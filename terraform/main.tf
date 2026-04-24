locals {
  # Extract plain IP addresses (without prefix length) for output and tagging
  node_ips = {
    for name, node in var.nodes :
    name => split("/", node.ip)[0]
  }
}

resource "proxmox_virtual_environment_vm" "nixos" {
  for_each = var.nodes

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vm_id

  # Do not auto-start — nixos-anywhere handles the initial boot and install
  on_boot = false
  started = false

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  # Blank root disk — disko will partition it during nixos-anywhere provisioning
  disk {
    datastore_id = each.value.datastore
    size         = each.value.disk_size
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
  }

  # NixOS installer ISO attached for the initial boot
  cdrom {
    enabled   = true
    file_id   = var.nixos_iso
    interface = "ide2"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # QEMU guest agent for Proxmox integration (start/stop, IP reporting)
  agent {
    enabled = true
  }

  # Boot from disk first; fall back to CDROM for the initial install
  boot_order = ["scsi0", "ide2"]

  # Prevent Terraform from reverting boot order or CDROM config after the
  # first nixos-anywhere provisioning run (when the CDROM is no longer needed)
  lifecycle {
    ignore_changes = [
      boot_order,
      cdrom,
      started,
    ]
  }
}
