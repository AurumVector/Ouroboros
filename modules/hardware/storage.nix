# =============================================================================
# modules/hardware/storage.nix — NVMe/HDD I/O Schedulers, TRIM & Firmware
# =============================================================================
# ARCHITECTURE BLUEPRINT (Storage I/O Optimization):
#
#   NVMe Tier (Samsung 990 Pro / Sabrent Rocket):
#     ├── Scheduler: "none" (Bypasses kernel block layer scheduling).
#     │   Rationale: Modern PCIe 4.0 NVMe controllers handle their own NCQ 
#     │   (Native Command Queuing) faster than the host CPU can organize it.
#     ├── Read-Ahead: 128KB (Conservative). NVMe excels at random access; 
#     │   aggressive prefetching wastes memory and bandwidth.
#     └── Firmware: Automated LVFS updates via fwupd.
#
#   Rotational Tier (2TB HDD):
#     ├── Scheduler: "bfq" (Budget Fair Queuing).
#     │   Rationale: Provides excellent latency guarantees for interactive tasks
#     │   while a background process is heavily accessing the mechanical drive.
#     └── Read-Ahead: 4096KB (Aggressive). Mitigates mechanical seek times 
#         during sequential reads.
#
#   NAND Maintenance:
#     └── Weekly fstrim explicitly enabled as a safety net alongside the 
#         real-time 'discard=async' Btrfs mount option.
# =============================================================================

{ pkgs, ... }:

{
  # ── SSD/NVMe Block Discard (TRIM) ────────────────────────────────────────
  # Complements the real-time Btrfs 'discard=async' to ensure no orphaned 
  # blocks are left behind over time, maintaining optimal LUKS/NVMe performance.
  services.fstrim = {
    enable   = true;
    interval = "weekly";
  };

  # ── Low-Level I/O Scheduler Rules (udev) ─────────────────────────────────
  services.udev.extraRules = ''
    # ── NVMe PCIe Fabric ──
    # Target: nvme0n1 (CyberLab) & nvme1n1 (Primary Forge)
    # Strip away kernel-level I/O scheduling to minimize latency overhead.
    ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", \
      ATTR{queue/scheduler}="none", \
      ATTR{queue/read_ahead_kb}="128"

    # ── Rotational Storage (SATA HDD) ──
    # Enforce fair bandwidth distribution and aggressive read-ahead to 
    # compensate for physical mechanical limitations.
    ACTION=="add|change", KERNEL=="sd[a-z]", \
      ATTR{queue/rotational}=="1", \
      ATTR{queue/scheduler}="bfq", \
      ATTR{queue/read_ahead_kb}="4096"
  '';

  # ── Autonomous Firmware Upgrades (LVFS) ──────────────────────────────────
  # Critical for patching zero-day vulnerabilities in NVMe controllers and UEFI 
  # without relying on external bootable media.
  services.fwupd.enable = true;

  # ── File System Support Declaration ──────────────────────────────────────
  boot.supportedFilesystems = [ "btrfs" ];
}
