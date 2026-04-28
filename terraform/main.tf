resource "proxmox_virtual_environment_vm" "nixos" {
  for_each = var.nodes

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vm_id
  on_boot = true
  started = true

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

# Poll each Proxmox node via SSH until the VM reaches 'running' state.
# Retries up to 30 times with 10s sleep (5-minute total timeout).
# If the VM never starts, the provisioner fails and apply returns an error.
# Note: VMs are created with started = false — this provisioner is intended
# for use after nixos-anywhere has booted the VM. Re-trigger manually with:
#   tofu taint 'null_resource.vm_started["<hostname>"]'
resource "null_resource" "vm_started" {
  for_each = var.nodes

  triggers = {
    vm_id = each.value.vm_id
  }

  connection {
    type        = "ssh"
    host        = each.value.node
    user        = "root"
    private_key = file(pathexpand(var.pve_ssh_private_key_file))
  }

  provisioner "remote-exec" {
    inline = [
      "for i in $(seq 1 30); do STATUS=$(qm status ${each.value.vm_id} | awk '{print $2}'); echo \"Attempt $i/30: VM ${each.value.vm_id} status = $STATUS\"; [ \"$STATUS\" = \"running\" ] && echo \"VM ${each.value.vm_id} is running.\" && exit 0; sleep 10; done; echo \"ERROR: VM ${each.value.vm_id} did not reach running state within 5 minutes.\"; exit 1"
    ]
  }

  depends_on = [proxmox_virtual_environment_vm.nixos]
}
