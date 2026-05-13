output "temporary_bootstrap_ips" {
  description = "The DHCP IPs used by nixos-anywhere. (Check your NixOS Flakes for the permanent IPs)."
  value = {
    for hostname in keys(proxmox_virtual_environment_vm.nixos) :
    hostname => coalesce(local.guest_ipv4_by_node[hostname], "IP pending...")
  }
}

output "vm_network_endpoints" {
  description = "Provisioned VM network endpoints (bootstrap IP and NIC MAC address)."
  value = {
    for hostname, vm in proxmox_virtual_environment_vm.nixos :
    hostname => {
      ip  = coalesce(local.guest_ipv4_by_node[hostname], "IP pending...")
      mac = try(vm.network_device[0].mac_address, null)
    }
  }
}
