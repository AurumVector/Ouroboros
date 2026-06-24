# =============================================================================
# modules/profiles/mining/default.nix — Cryptographic Hashing & Compute Node
# =============================================================================
# ARCHITECTURE OBJECTIVE (MAXIMUM HASHRATE EFFICIENCY):
#   Transform the Ouroboros workstation into a dedicated computational node
#   optimized for the RandomX algorithm (Monero/XMR).
#
# BARE-METAL TUNING DOCTRINE:
#   ├── 1. MSR Manipulation: The Model-Specific Registers (MSR) kernel module 
#   │      is injected to allow XMRig to disable hardware prefetchers. This 
#   │      eliminates cache thrashing and boosts RandomX performance by ~15%.
#   ├── 2. L3 Cache Alignment: The Ryzen 9 5950X features 64MB of L3 Cache. 
#   │      RandomX requires 2MB per thread. 32 threads exactly saturate the L3, 
#   │      making this a mathematically perfect architecture.
#   ├── 3. Memory Subsystem: 6GB of static 2MB Hugepages are reserved to hold 
#   │      the RandomX dataset, reducing Translation Lookaside Buffer (TLB) misses.
#   └── 4. Thermal Management: The RTX 4070 is strictly power-capped (undervolted) 
#          via systemd to minimize chassis ambient temperature, granting the 
#          CPU maximum Precision Boost Overdrive (PBO) thermal headroom.
# =============================================================================

{ config, pkgs, lib, ... }:

{
  # ── Tier 1: Hardware Interfacing (MSR & Hugepages) ───────────────────────
  # Load the MSR module into the kernel during the boot process.
  boot.kernelModules = [ "msr" ];

  boot.kernel.sysctl = {
    # Reserve 3072 pages of 2MB (Total: 6GB) specifically for the XMRig Dataset.
    # With 48GB of total system RAM, this allocation is perfectly safe.
    "vm.nr_hugepages" = lib.mkForce 3072;
    
    # Allow unprivileged processes to lock memory (Required for 1GB Hugepages)
    "vm.max_map_count" = lib.mkForce 262144;
  };

  # ── Tier 2: Thermal & GPU Power Capping ──────────────────────────────────
  # Since RandomX is CPU-bound, the RTX 4070 is idled and power-capped to 100W.
  # This prevents GPU heat bleed into the CPU cooling block.
  systemd.services.nvidia-power-limit = {
    description = "Limit NVIDIA RTX 4070 Power Draw for Mining Acoustics";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.linuxPackages.nvidia_x11.bin}/bin/nvidia-smi -pl 100";
      RemainAfterExit = true;
    };
  };

  # ── Tier 3: XMRig Service Orchestration ──────────────────────────────────
  services.xmrig = {
    enable = true;
    
    settings = {
      autosave = true;
      
      # CPU Tuning Matrix
      cpu = {
        enabled = true;
        huge-pages = true;
        hw-aes = true;
        priority = 5; # Aggressive thread priority
        
        # MSR modding requires CAP_SYS_ADMIN, applied by NixOS natively
        memory-pool = false;
        yield = true;
        asm = true;
      };

      # Disable GPU mining to favor CPU thermals and efficiency
      opencl = false;
      cuda   = false;

      # Mining Pool Matrix (Hashvault Integration)
      pools = [
        {
          url = "pool.hashvault.pro:443";
          # The wallet is injected via sops-nix or external secret file in production
          user = "\${XMR_WALLET_ADDRESS}"; 
          pass = "OuroborosNode";
          tls  = true;
          keepalive = true;
          nicehash = false;
        }
      ];
    };
  };

  # ── Tier 4: Systemd Service Hardening ────────────────────────────────────
  # Elevate XMRig to bypass standard memory constraints
  systemd.services.xmrig = {
    serviceConfig = {
      LimitMEMLOCK = "infinity"; # Unrestricted Hugepage locking
      Nice         = -10;        # High CPU scheduler priority
      
      # Strict isolation: Only allow network access and CPU math
      ProtectHome   = true;
      ProtectSystem = "strict";
      PrivateTmp    = true;
    };
  };

  # ── Tier 5: Host-Level Eviction (Reclaiming Resources) ───────────────────
  # Eliminate all non-essential workloads to guarantee 0% CPU jitter.
  programs.steam.enable          = lib.mkForce false;
  programs.gamemode.enable       = lib.mkForce false;
  services.ollama.enable         = lib.mkForce false;
  virtualisation.libvirtd.enable = lib.mkForce false;
  virtualisation.podman.enable   = lib.mkForce false;

  # ── Telemetry Toolchain ──────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    lm_sensors  # Core temperature and fan speed monitoring
    btop        # Advanced TUI resource monitor
    nvtopPackages.nvidia # GPU telemetry to ensure deep sleep state
  ];
}
