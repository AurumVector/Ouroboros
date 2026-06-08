# =============================================================================
# modules/hardware/memory.nix — VM Subsystem, ZRAM & Hugepages
# =============================================================================
# ARCHITECTURE DIRECTIVE:
#   This module is the SINGLE SOURCE OF TRUTH for all vm.* sysctl parameters.
#   Never inject vm.* parameters in other modules. Operational profiles (e.g., 
#   cyberlab, mining) must use lib.mkForce to override specific values.
#
# HARDWARE CONTEXT (Infinity Fabric Tuning):
#   RAM: 32GB DDR4 G.Skill Trident Z Neo (2x16GB Dual Channel / Slots A2 & B2)
#   Target FCLK (Fabric Clock): 1800-1933MHz (Subject to stability testing)
#
# ZRAM DOCTRINE (In-Memory Compression):
#   Allocates 25% of total RAM (~8GB) as a high-speed, zstd-compressed block 
#   device. Swappiness is intentionally set to 150; with ZRAM, a high value 
#   instructs the kernel to proactively compress memory rather than waiting 
#   for severe memory pressure, significantly increasing effective capacity 
#   without disk I/O latency.
#
# HUGEPAGES STRATEGY:
#   Base: 0 static + THP madvise (On-demand allocation).
#   LLM Profile: Overridden to 512 static (1GB) for CUDA buffers + THP always.
#   Mining Profile: Overridden to 1280 static (2.5GB) for RandomX dataset.
# =============================================================================

{ ... }:

{
  # ── ZRAM Compressed Swap Device ──────────────────────────────────────────
  zramSwap = {
    enable        = true;
    algorithm     = "zstd";
    memoryPercent = 25; # Dynamic allocation (~8GB of 32GB pool)
  };

  # ── Transparent Hugepages (THP) Baseline ─────────────────────────────────
  # "madvise": Conservative approach. Only apply THP to applications that 
  # explicitly request it, preventing memory fragmentation in standard workloads.
  boot.kernelParams = [ "transparent_hugepage=madvise" ];

  # ── Kernel VM Subsystem Tuning (sysctl) ──────────────────────────────────
  boot.kernel.sysctl = {
    # ── ZRAM Optimization ──
    # High swappiness (150/200) is optimal for ZRAM, encouraging early 
    # compression into the block device. Without ZRAM, this would cause thrashing.
    "vm.swappiness" = 150;

    # Disable read-ahead for compressed swap. Since ZRAM is in memory, reading 
    # pages in clusters (the default behavior for physical disks) wastes CPU 
    # cycles decompressing data that wasn't requested.
    "vm.page-cluster" = 0;

    # ── Memory Fragmentation & Latency ──
    # Disable proactive memory compaction. While useful for low-RAM systems, 
    # background compaction causes unpredictable micro-stuttering in high-RAM 
    # (32GB) environments, severely impacting CS2 frame times.
    "vm.compaction_proactiveness" = 0;

    # Increase maximum memory map areas. Critical for modern Proton gaming 
    # and large LLM memory mapping.
    "vm.max_map_count" = 2147483642;

    # ── NVMe I/O Commit Strategy ──
    # Aggressive flushing of dirty pages. With a high-throughput NVMe 
    # (Samsung 990 Pro), flushing is computationally cheap. This minimizes 
    # data loss windows during hard crashes.
    "vm.dirty_ratio"            = 10;
    "vm.dirty_background_ratio" = 3;

    # ── Static Hugepages Allocation ──
    # Base configuration requests zero static hugepages. 
    # Overridden dynamically by specialisations via lib.mkForce.
    "vm.nr_hugepages"            = 0;
    "vm.nr_overcommit_hugepages" = 0;
  };
}
