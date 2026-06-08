# =============================================================================
# modules/hardware/cpu.nix — AMD Ryzen 9 5950X (Zen 3 / Vermeer)
# =============================================================================
# HARDWARE TOPOLOGY & PERFORMANCE DOCTRINE:
#   - Asymmetric Architecture: 16 Cores / 32 Threads split across 2 CCDs
#     (Core Chiplet Dies) containing 8 cores each.
#   - Preferred Cores: Core 0 (CCD0) and Core 8 (CCD1) hold the highest silicon 
#     quality for maximum single-thread boost frequencies.
#   - The 80ns Bottleneck: Inter-CCD communication incurs an ~80ns latency 
#     penalty (L3 cache miss). Latency-critical workloads (CS2, CyberLab VMs) 
#     must be thread-pinned to a single CCD to maintain IPC efficiency.
#
# FIRMWARE & SCHEDULING STRATEGY:
#   - amd_pstate=active: Governed globally via core/boot.nix for EPP control.
#   - PBO & Curve Optimizer: Delegated strictly to UEFI for hardware-level 
#     stability. No software-level undervolting applied in NixOS.
#   - eBPF scx_lavd: Topology-aware scheduler handles baseline thread placement.
# =============================================================================

{ config, lib, pkgs, ... }:

{
  # ── Hardware Virtualization (KVM) ────────────────────────────────────────
  # Mandatory for CyberLab Hypervisor isolation and high-performance VMs.
  boot.kernelModules = [ "kvm-amd" ];

  # ── Silicon Microcode ────────────────────────────────────────────────────
  # Dynamically patch AMD CPU vulnerabilities (e.g., Spectre, Meltdown, Inception) 
  # during early Stage-1 boot without requiring immediate UEFI BIOS flashes.
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ── CPU Telemetry & Topology Toolchain ───────────────────────────────────
  # Injected explicitly to manage Zen 3 NUMA-like behavior and monitor P-states.
  environment.systemPackages = with pkgs; [
    # Process Pinning: Allows binding critical processes (e.g., CS2, libvirt VMs) 
    # explicitly to CCD0 to eliminate inter-CCD latency penalties.
    numactl
    
    # Hardware Locality: CLI tools (lstopo) to visualize L1/L2/L3 cache sharing
    hwloc
    
    # Kernel-level frequency scaling and P-state diagnostics
    linuxPackages.cpupower
    
    # AMD Zen-specific hardware monitoring (Core voltages, exact package temps)
    zenmonitor
  ];
}
