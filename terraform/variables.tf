variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL (e.g. https://pve01.home.lab:8006/)"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox API username (e.g. terraform@pve)"
  type        = string
}

variable "proxmox_password_file" {
  description = "Path to a file containing the Proxmox API password (e.g. ~/.proxmox-password)"
  type        = string
}

variable "proxmox_insecure" {
  description = "Skip TLS certificate verification (set true for self-signed certs)"
  type        = bool
  default     = true
}

variable "nixos_iso" {
  description = "Proxmox storage path for the NixOS installer ISO (e.g. local:iso/nixos-installer.iso)"
  type        = string
}

variable "nodes" {
  description = "Map of NixOS VM definitions. Hardware specs only — OS config (including networking) is handled by nixos-anywhere via the flake."
  type = map(object({
    node      = string # Proxmox cluster node to host the VM (e.g. pve01)
    vm_id     = number # Unique VM ID within the Proxmox cluster
    cores     = number # Number of vCPU cores
    memory    = number # RAM in MiB
    disk_size = number # Root disk size in GiB
    datastore = string # Proxmox storage pool for the disk (e.g. local-lvm)
  }))
  default = {}
}
