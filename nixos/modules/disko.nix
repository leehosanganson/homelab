{ ... }: {
  boot.initrd.availableKernelModules = [
    "virtio_scsi"   # virtio-scsi disk (scsi0 in Proxmox)
    "virtio_pci"    # virtio PCI bus
    "virtio_blk"    # virtio-blk fallback
    "ahci"          # SATA fallback
    "sd_mod"        # SCSI disk driver
    "ext4"          # root filesystem
  ];

  boot.loader.grub = {
    enable = true;
  };

  disko.devices = {
    disk = {
      main = {
        type   = "disk";
        device = "/dev/sda"; # virtio-scsi (scsi0 in terraform/main.tf) → /dev/sda
        content = {
          type = "gpt";
          partitions = {
            # BIOS boot partition required for GRUB on GPT with legacy BIOS
            boot = {
              size = "1M";
              type = "EF02";
            };
            root = {
              size    = "100%";
              content = {
                type       = "filesystem";
                format     = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
