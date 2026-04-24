{ ... }: {
  disko.devices = {
    disk = {
      main = {
        type   = "disk";
        device = "/dev/sda";
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
