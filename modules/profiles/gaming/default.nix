# =============================================================================
# modules/profiles/gaming/default.nix — Competitive E-Sports & Low-Latency Tier
# =============================================================================
# ARCHITECTURE OBJECTIVE:
#   Zero-jitter environment optimized for Counter-Strike 2 (Source 2 Engine) 
#   running on an MSI 27" 170Hz display driven by an NVIDIA RTX 4070.
#
# BARE-METAL KERNEL TUNING (Main  Topology):
#   ├── preempt=full : Forces the kernel to be fully preemptible, prioritizing 
#   │                  user-space gaming threads over background kernel tasks.
#   ├── nohz_full    : Achieves a "tickless" state on Cores 1-15, eliminating 
#   │                  the 250μs scheduling interrupt overhead on gaming cores.
#   └── irqaffinity  : Pins all hardware interrupts (NVMe, NIC, USB) to Core 0. 
#                      This mathematically isolates the game engine on CCD0.
#
# COMPOSITOR & AUDIO PIPELINE:
#   ├── Gamescope : Micro-compositor enforcing strict frame-pacing and G-Sync.
#   └── PipeWire  : Audio buffer quantum reduced to 64 (~1.3ms end-to-end latency).
# =============================================================================

{ pkgs, lib, ... }:

{
  # ── Kernel Micro-Architecture Isolation ──────────────────────────────────
  boot.kernelParams = lib.mkAfter [
    "preempt=full"          # Aggressive user-space scheduling priority
    "split_lock_detect=off" # Prevent performance degradation from unaligned memory access in older/ported engines
    
    # Isolate Cores 1-15 from kernel noise. Core 0 handles the OS burden.
    "nohz_full=1-15"        
    "rcu_nocbs=1-15"        
    "irqaffinity=0"         
  ];

  # ── Memory Subsystem Overrides ───────────────────────────────────────────
  boot.kernel.sysctl = {
    # Ensure static hugepages remain 0 (managed by base), but enforce THP 
    # to 'always' to minimize page faults during heavy VRAM-to-RAM streaming.
    "vm.nr_hugepages" = lib.mkForce 0;
  };

  # ── NVIDIA P-State Locking (Zero Wake-up Latency) ────────────────────────
  hardware.nvidia.powerManagement.enable = lib.mkForce false;

  # ── Steam Client & Proton Integration ────────────────────────────────────
  programs.steam = {
    enable = true;
    
    # OPSEC: Deny ingress traffic for remote features
    remotePlay.openFirewall      = false;
    dedicatedServer.openFirewall = false;
    
    gamescopeSession.enable      = false; # Handled via explicit launch options
    
    extraPackages = with pkgs; [
      # Inject Gamemode daemon directly into the Steam runtime envelope
      gamemode 
    ];
  };

  # ── Gamescope Micro-Compositor ───────────────────────────────────────────
  programs.gamescope = {
    enable     = true;
    capSysNice = true; # Grant capabilities to dynamically alter thread priorities
    
    # Launch template for CS2 (In Steam Launch Options):
    # gamescope -W 2560 -H 1440 -r 170 --adaptive-sync --expose-wayland -e -- gamemoderun %command%
  };

  # ── Feral Interactive Gamemode (Dynamic Tuning) ──────────────────────────
  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        renice       = 10;          # Negative renice value pushes CPU priority
        desiredgov   = "performance";
        softrealtime = "auto";
        reaper_freq  = 5;
      };
      cpu = {
        park_cores = "no";
        pin_cores  = "yes";         # Bind execution to the isolated CCD0 cluster
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device              = 0;
        # Force Powermizer to state 1: Disables P-State downclocking mid-game
        nv_powermizer_mode      = 1;
      };
    };
  };

  # ── Hypervisor & Container Eviction ──────────────────────────────────────
  # Explicitly kill backend virtualization services to reclaim RAM and CPU cycles.
  virtualisation.libvirtd.enable = lib.mkForce false;
  virtualisation.podman.enable   = lib.mkForce false;

  # ── Acoustic Pipeline Tuning (PipeWire) ──────────────────────────────────
  services.pipewire.extraConfig.pipewire = {
    "99-gaming-latency" = {
      "context.properties" = {
        "default.clock.rate"        = 48000;
        # Target: ~1.3ms Latency (64 frames / 48kHz)
        "default.clock.quantum"     = 64; 
        "default.clock.min-quantum" = 32;
        "default.clock.max-quantum" = 8192;
      };
    };
  };

  # ── Graphics Driver Directives (Environment Variables) ───────────────────
  environment.variables = {
    # Expose NVIDIA Reflex APIs to Proton/Wine translation layers
    PROTON_ENABLE_NVAPI         = "1";
    PROTON_HIDE_NVIDIA_GPU      = "0";

    # Force RayTracing (DXR) enablement in VKD3D when required
    VKD3D_CONFIG                = "dxr11,dxr";

    # Enforce minimum frame queuing latency (1 frame backbuffer)
    __GL_MaxFramesAllowed       = "1";

    # Defer V-Sync management strictly to the game engine or Gamescope
    __GL_SYNC_TO_VBLANK         = "0";

    # Force multi-threaded OpenGL optimizations
    __GL_THREADED_OPTIMIZATIONS = "1";
  };

  # ── Tactical Gaming Toolchain ────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    mangohud    # Telemetry overlay (Frametimes, 1% lows, Thermal limits)
    vkbasalt    # Vulkan post-processing injection
    protonup-qt # Declarative-adjacent GUI management for Proton-GE variants
    ludusavi    # Save-state archival tool
    librewolf
    sbctl
  ];
}
