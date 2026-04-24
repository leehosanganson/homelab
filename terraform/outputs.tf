output "vm_ids" {
  description = "Proxmox VM IDs keyed by hostname"
  value       = { for name, vm in proxmox_virtual_environment_vm.nixos : name => vm.vm_id }
}

output "node_ips" {
  description = "Static IP addresses keyed by hostname (use with provision.sh / rebuild.sh)"
  value       = local.node_ips
}
