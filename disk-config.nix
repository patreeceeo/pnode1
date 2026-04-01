# disk-config.nix – BIOS layout for RackNerd KVM (legacy BIOS/SeaBIOS mode)
{ lib, ... }:

{
  disko.devices = {
    disk = {
      vda = {
        # RackNerd always uses /dev/vda (virtio)
        device = lib.mkDefault "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # BIOS boot partition (unformatted, required for GRUB on GPT)
            bios = {
              size = "1M";
              type = "EF02";  # BIOS boot
            };
            # Main root partition (takes the rest)
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
