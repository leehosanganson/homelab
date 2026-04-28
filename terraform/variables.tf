variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL (e.g. https://pve01.home.lab:8006/)"
  type        = string
}

variable "proxmox_api_token_file" {
  description = "Path to a file containing the Proxmox API token string; format: user@realm!tokenid=secret (e.g. terraform@pam!homelab=<uuid-secret>). Contents are read at plan/apply time via file()."
  type        = string
}

variable "proxmox_insecure" {
  description = "Skip TLS certificate verification only when explicitly set to true (for example, with self-signed certs)"
  type        = bool
  default     = false
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
    ip        = string # Static IP address assigned to the VM by the NixOS configuration
  }))
  default = {}
}

variable "pve_ssh_private_key_file" {
  description = "Path to the SSH private key used to connect to Proxmox nodes as root (e.g. ~/.ssh/id_ed25519). Used by the vm_started provisioner to poll qm status over SSH."
  type        = string
}
