variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint URL"
  type        = string
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for self-signed certificates"
  type        = bool
  default     = true
}

variable "nodes" {
  description = "Map of VM nodes to provision on Proxmox"
  type = map(object({
    target_node = string
    vm_id       = number
    cores       = number
    memory      = number
    disk_size   = number # GB
    storage     = string
    bridge      = string
  }))
}
