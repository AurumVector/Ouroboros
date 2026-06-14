# =============================================================================
# modules/core/boot.nix — Kernel, Bootloader, and eBPF Scheduling
# =============================================================================
# ARCHITECTURE OVERVIEW:
#   Defines the foundation of the Ouroboros operating environment. 
#   Strictly manages the boot sequence, hardware-level mitigations, and 
#   task scheduling strategies tailored for the Zen 3 / Ada Lovelace topology.
#
# KERNEL STRATEGY: linuxPackages_6_12 (LTS)
#   ├── Rationale: Proven stability with proprietary NVIDIA drivers.
#   ├── Features: Native PREEMPT_DYNAMIC support and mainline sched_ext.
#   └── Constraint Mitigations: Kernel lockdown is deliberately not set to 
#       'confidentiality' to prevent breaking NVIDIA proprietary module loading.
#       (Integrity mode remains viable if strictly required).
#
# SCHEDULING: scx_lavd (Latency-based Virtual Deadline)
#   ├── eBPF-based scheduler dynamically loaded via sched_ext.
#   ├── Topologically aware of Zen 3 architecture (CCDs, preferred cores).
#   └── Prioritizes interactive latency under heavy concurrent loads without 
#       starving background processes (e.g., compile/mining tasks).
# =============================================================================

{ config, pkgs, lib, ... }:

{
  # ── Kernel Definition ──────────────────────────────────────────────────
  boot.kernelPackages = pkgs.linuxPackages_6_12;

  # ── Global Kernel Parameters ───────────────────────────────────────────
  # Base parameters applied across ALL operational profiles. 
  # Profile-specific parameters must be appended via lib.mkAfter elsewhere.
  boot.kernelParams = [
    "quiet"
    "loglevel=3"

    # AMD P-State (Active Mode / EPP)
    # Replaces legacy acpi_cpufreq for granular, per-core frequency scaling.
    "amd_pstate=active"

    # IOMMU & Virtualization (CyberLab Foundation)
    # amd_iommu=on: Enforces strict device isolation for KVM/QEMU.
    # iommu=pt: Passthrough mode. Eliminates translation overhead for 
    # devices NOT actively passed to a virtual machine.
    "amd_iommu=on"
    "iommu=pt"

    # Hardware Watchdog Disable
    # Eliminates periodic timer interrupts, reducing latency jitter on the 
    # 5950X during intensive workstation/gaming loads.
    "nowatchdog"
    "nmi_watchdog=0"

    # Hardware Vulnerability Mitigations
    # Defers to the kernel's automatic selection based on CPU generation.
    # For Zen 3: retpoline + IBRS + reduced STIBP.
    "mitigations=auto"
  ];

  # ── Early Boot Environment (Stage-1) ───────────────────────────────────
  # systemd-based initrd is mandatory for the Ouroboros architecture:
  #   1. Deterministic Btrfs root rollbacks (Impermanence).
  #   2. Declarative LUKS unlocking with configurable keyfile timeouts.
  environment.systemPackages = with pkgs; [
  sbctl
  ];

  boot = { 
    initrd.systemd.enable = true;
    supportedFilesystems = [ "btrfs" "vfat" ];
  
  loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
     };
   };

  # ── Dynamic eBPF Scheduler ─────────────────────────────────────────────
  # Active globally. Do not override in specialisations; scx_lavd natively 
  # adapts its heuristics based on workload detection.
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
    # Omitted extraArgs forces scx_lavd to perform automatic topology discovery.
  };
}
