output "vm_ids" {
  description = "Map of node names to their Proxmox VM IDs"
  value       = { for name, vm in proxmox_virtual_environment_vm.nodes : name => vm.vm_id }
}
