resource "proxmox_virtual_environment_vm" "nixos" {
  for_each = var.nodes

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vm_id

  on_boot = true
  started = true

  operating_system {
    type = "l26"
  }

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

  # Prevent OpenTofu from reverting boot order or CDROM config after the
  # first nixos-anywhere provisioning run (when the CDROM is no longer needed)
  lifecycle {
    ignore_changes = [
      boot_order,
      cdrom,
      started,
    ]
  }
}

# Wait for the Guest OS to be ready for nixos-anywhere
resource "terraform_data" "wait_for_guest_ssh" {
  for_each = var.nodes

  # Re-run if the VM ID changes
  triggers_replace = [
    proxmox_virtual_environment_vm.nixos[each.key].id
  ]

  # SSH into the actual Guest VM (not the Proxmox host)
  connection {
    type        = "ssh"
    user        = "root"
    host        = proxmox_virtual_environment_vm.nixos[each.key].ipv4_addresses[1][0]
    private_key = file(pathexpand(var.pve_ssh_private_key_file))
    timeout     = "5m"
  }

  # Confirm the VM is fully booted and ready for provisioning before running the local provisioning script
  provisioner "remote-exec" {
    inline = [
      "echo 'VM ${each.value.vm_id} has fully booted NixOS and is ready for provisioning!'"
    ]
  }

  # Run the local provisioning script with the VM name and IP address as arguments
  provisioner "local-exec" {
    command = "../nixos/scripts/provision.sh ${each.key} ${try(proxmox_virtual_environment_vm.nixos[each.key].ipv4_addresses[1][0], "")}"
  }
}

