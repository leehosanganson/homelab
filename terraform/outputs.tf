output "temporary_bootstrap_ips" {
  description = "The DHCP IPs used by nixos-anywhere. (Check your NixOS Flakes for the permanent IPs)."
  value = {
    for hostname, vm in proxmox_virtual_environment_vm.nixos : 
    hostname => try(vm.ipv4_addresses[1][0], "IP pending...")
  }
}
