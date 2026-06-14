# =============================================================================
# lib/hardware-ids.nix — Centralized Hardware Identifiers (Portable Layer)
# =============================================================================
# DESIGN GOAL:
#   Fully reproducible NixOS deployments across multiple machines.
#
# STRATEGY:
#   ├── Prefer /dev/disk/by-id (stable across reboots and hardware order changes)
#   ├── UUID only when by-id is not available (LUKS, filesystems)
#   ├── Single source of truth for all disk references
#   └── No direct /dev/sdX usage anywhere in the system
#
# WHY THIS EXISTS:
#   Device names (/dev/nvme0n1, /dev/sda) are NOT stable.
#   UUIDs are stable but not human-readable.
#   by-id is stable + readable + portable → preferred abstraction layer.
#
# HOW TO FILL:
#   blkid -s UUID -o value /dev/nvme1n1p1 ( EFI partition for encryption )
#   blkid -s UUID -o value /dev/nvme1n1p2 ( Main partition )
#   blkid -s UUID -o value /dev/nvme0n1p1 ( CyberLab )
#   blkid -s UUID -o value /dev/sdb1 ( HDD 2TB )
#
#   ls -l /dev/disk/by-id/
#   ls /dev/disk/by-id/ | grep "^usb-" | grep -v "part" (USB KEY)
#
# IMPORTANT RULE:
#   If a by-id path exists → ALWAYS prefer it over UUID.
# =============================================================================

{
  uuids = {
    # Main system LUKS container (Samsung 990 Pro 1TB)
    luksNvmeMain = "c0cda2bf-e902-4cfa-aec6-9df6ddb4b6ff";

    # EFI System Partition (bootloader target)
    efiPartition = "F46D-8EFC";

    # Secondary LUKS container (Sabrent NVMe 512GB / CyberLab)
    luksSabrent = "de1fa47b-bb1b-4a68-9218-746fb0e4a4fd";

    # HDD storage partition (2TB XFS dataset)
    hddStorage = "6327bc84-3235-4d7e-9842-371319b27765";
    
    # SATA SDD Partition (256GB - cryptmodels)
    luksSataSsd = "f0989296-6084-4527-a78c-e76d148cc7a4";
    
    # BTRFS subvolume within cryptmodels
    cryptModelsFs = "da17025a-2c57-490b-a10c-2804af9c5065";
  };

  byId = {
    # USB encryption / boot key (must use persistent by-id path)
    # Example format:
    # usbKey = "/dev/disk/by-id/usb-SanDisk_Cruzer_Blade_XXXX";
    usbKey = "/dev/disk/by-id/usb-VendorCo_ProductCode_6984951167393631269-0:0";

    # Optional: raw disk identifiers (recommended for declarative disk config)
    # nvmeMain = "/dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HBLR-00000";
    # nvmeLab  = "/dev/disk/by-id/nvme-Sabrent_ROCKET_512GB_XXXX";
    # hddData  = "/dev/disk/by-id/ata-ST2000LMXXXX";
    # luksSataSsd = "/dev/disk/by-id/XXXXXXXXX";
  };
}
