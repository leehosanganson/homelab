terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}

provider "proxmox" {
  endpoint      = var.proxmox_endpoint
  username      = var.proxmox_username
  password_file = pathexpand(var.proxmox_password_file)
  insecure      = var.proxmox_insecure
}
