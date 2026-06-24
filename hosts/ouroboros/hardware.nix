# =============================================================================
# hosts/ouroboros/hardware.nix — Hardware Abstraction & Early Boot Layer
# =============================================================================
# ARCHITECTURE OVERVIEW:
#   Bare-metal hardware declaration for the Ouroboros primary workstation.
#   Abstracts away auto-generated hardware logic to maintain strict declarative
#   control over early boot sequences, cryptographic key retrieval, and
#   hypervisor (KVM) enablement.
#
# HARDWARE TARGET:
#   CPU:  AMD Ryzen 9 5950X (Zen 3 / Vermeer)
#   GPU:  NVIDIA RTX 4070 (Ada Lovelace)
#   Disk: Samsung 990 Pro 1TB (NVMe) + Sabrent 512GB (NVMe) + 2TB HDD
#
# SECURITY NOTE:
#   initrd modules are strictly limited to components required for
#   Stage-1 LUKS decryption (via USB keyfile) and base root mounting.
#   File systems are decoupled and managed in core/filesystem.nix.
# =============================================================================

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];
  # ── Kernel Parameters (IOMMU ENABLE) ──────────────────────────────
  boot.kernelParams = [
    "amd_iommu=on"
    "iommu=pt"
];

 # ── GPU HOST DRIVER BLOCK ────────────────────────────────────────
  boot.blacklistedKernelModules = [
    "nouveau"
  ];

  # ── INITRD VFIO EARLY LOAD ────────────────────────────────────────
  boot.initrd.kernelModules = [
    "vfio"
    "vfio_pci"
    "vfio_iommu_type1"
  ];

  # ── Stage-1 Bootloader (initrd) Modules ──────────────────────────────
  # Minimal surface area: Only load modules critical for decrypting 
  # the system and mounting the root file system before user-space loads.
  boot.initrd.availableKernelModules = [
    "nvme"          # High-speed storage protocol (Primary/Lab NVMes)
    "xhci_pci"      # USB 3.x PCI controller (Critical for LUKS USB keyfile)
    "xhci_hcd"      # USB Host Controller generic driver
    "ahci"          # SATA controller (Secondary 2TB HDD)
    "usb_storage"   # USB mass storage support (Boot/Key sequence)
    "uas"           # USB Attached SCSI (High-throughput USB 3.x protocol)
    "sd_mod"        # SCSI disk generic support
  ];

  # ── User-Space Kernel Modules ────────────────────────────────────────
  boot.kernelModules = [
    "kvm-amd"       # AMD-V Virtualization (Critical for CyberLab hypervisors)
  ];

  boot.extraModulePackages = [ ];

  # ── Firmware & Microcode Layer ───────────────────────────────────────
  # Allows non-free firmware required by the RTX 4070, NVMe controllers, 
  # and the networking stack to function optimally.
  hardware.enableRedistributableFirmware = true;

  # Enforce AMD CPU microcode updates at boot to mitigate silicon-level 
  # vulnerabilities dynamically (e.g., Spectre/Meltdown mitigations).
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
