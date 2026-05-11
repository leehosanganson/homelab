output "temporary_bootstrap_ips" {
  description = "The DHCP IPs used by nixos-anywhere. (Check your NixOS Flakes for the permanent IPs)."
  value = {
    for hostname in keys(proxmox_virtual_environment_vm.nixos) :
    hostname => coalesce(local.guest_ipv4_by_node[hostname], "IP pending...")
  }
}
