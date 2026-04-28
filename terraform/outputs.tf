output "nixos_installer_ips" {
  description = "The dynamically assigned IPs of the newly booted NixOS VMs."
  value = {
    for hostname, vm in proxmox_virtual_environment_vm.nixos : 
    hostname => try(vm.ipv4_addresses[1][0], "IP pending Guest Agent...")
  }
}
