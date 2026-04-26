output "vm_ids" {
  description = "Proxmox VM IDs keyed by hostname"
  value       = { for name, vm in proxmox_virtual_environment_vm.nixos : name => vm.vm_id }
}
