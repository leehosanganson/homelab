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
    type  = var.use_host_instruction ? "host" : "x86-64-v3"
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
    bridge  = each.value.bridge
    model   = "virtio"
    vlan_id = try(each.value.vlan_tag, null)
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

locals {
  guest_usable_ipv4_candidates_by_node = {
    for hostname, vm in proxmox_virtual_environment_vm.nixos :
    hostname => try([
      for ip in flatten(vm.ipv4_addresses) : ip
      if ip != "" && ip != "0.0.0.0" && !startswith(ip, "127.") && !startswith(ip, "169.254.")
    ], [])
  }

  guest_rfc1918_ipv4_candidates_by_node = {
    for hostname, ips in local.guest_usable_ipv4_candidates_by_node :
    hostname => [
      for ip in ips : ip
      if startswith(ip, "10.") || startswith(ip, "192.168.") || can(regex("^172\\.(1[6-9]|2[0-9]|3[0-1])\\.", ip))
    ]
  }

  guest_ipv4_by_node = {
    for hostname, vm in proxmox_virtual_environment_vm.nixos :
    hostname => try(concat(
      local.guest_rfc1918_ipv4_candidates_by_node[hostname],
      local.guest_usable_ipv4_candidates_by_node[hostname]
    )[0], null)
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
    host        = local.guest_ipv4_by_node[each.key]
    private_key = file(pathexpand(var.pve_ssh_private_key_file))
    timeout     = "5m"
  }

  lifecycle {
    precondition {
      condition     = try(local.guest_ipv4_by_node[each.key], null) != null
      error_message = "No usable guest IPv4 for node '${each.key}' is available from the Proxmox guest agent yet (loopback/link-local/0.0.0.0 are ignored). Wait for the VM to finish booting and ensure qemu-guest-agent is running, then retry."
    }
  }

  # Confirm the VM is fully booted and ready for provisioning before running the local provisioning script
  provisioner "remote-exec" {
    inline = [
      "echo 'VM ${each.value.vm_id} has fully booted NixOS and is ready for provisioning!'"
    ]
  }

  # Run the local provisioning script with the VM name and IP address as arguments
  provisioner "local-exec" {
    command = "../nixos/scripts/provision.sh ${each.key} ${local.guest_ipv4_by_node[each.key]}"
  }
}
