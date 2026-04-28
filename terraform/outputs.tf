output "vm_ids" {
  description = "Proxmox VM IDs keyed by hostname"
  value       = { for name, vm in proxmox_virtual_environment_vm.nixos : name => vm.vm_id }
}

output "vm_summary" {
  description = "Summary of managed VMs: hostname → vm_id, node, and IP"
  value = {
    for name, vm in proxmox_virtual_environment_vm.nixos : name => {
      vm_id = vm.vm_id
      node  = var.nodes[name].node
      ip    = var.nodes[name].ip
    }
  }
}
