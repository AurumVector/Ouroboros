# =============================================================================
# modules/hardware/gpu.nix — NVIDIA RTX 4070 (Ada Lovelace / AD104) Pipeline
# =============================================================================
# ARCHITECTURE BLUEPRINT (NixOS 26.05 + Native Wayland):
#
#   DRIVER STRATEGY: hardware.nvidia.open = true
#     → For the Ada Lovelace architecture (RTX 40xx) on drivers 560+, NVIDIA 
#       officially mandates the transition to open-source kernel modules. 
#       This ensures better integration with kernel-level telemetry, lower 
#       latency interactions with the eBPF scheduler (scx_lavd), and superior 
#       native Wayland compatibility.
#
#   POWER MANAGEMENT:
#     → Base state enabled for workstation efficiency.
#     → Explicitly overridden (lib.mkForce false) in the gaming specialisation 
#       to eliminate wake-up latency during competitive CS2 scenarios.
#     → Governed by NVML daemon in the mining specialisation.
#
#   COMPOSITOR BACKEND: GBM (Generic Buffer Management) enforced globally.
# =============================================================================

{ config, pkgs, lib, ... }:

{
  # ── Graphics API & Hardware Acceleration (OpenGL/Vulkan/VA-API) ──────────
  # 'hardware.graphics' supersedes legacy 'hardware.opengl' as of NixOS 24.11+
  hardware.graphics = {
    enable      = true;
    enable32Bit = true; # Mandatory for Steam, Proton, and 32-bit Wine prefixes

    extraPackages = with pkgs; [
      nvidia-vaapi-driver # VA-API translation layer mapping over NVDEC hardware
      libva-vdpau-driver          # VA-API to VDPAU bridge backend
      libvdpau-va-gl      # VDPAU implementation via OpenGL
    ];

    extraPackages32 = with pkgs.pkgsi686Linux; [
      libvdpau-va-gl
    ];
  };

  # ── Display Server Driver Assignment ─────────────────────────────────────
  services.xserver.videoDrivers = [ "nvidia" ];

  # ── NVIDIA Kernel Module Configuration ───────────────────────────────────
  hardware.nvidia = {
    # DRM (Direct Rendering Manager) modesetting is strictly required for Wayland
    modesetting.enable = true;

    # Ada Lovelace architecture relies on the Open Source kernel modules
    open = true;

    # Pin to the stable branch mapping for NixOS 26.05 (Targeting 560+ branch)
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # Runtime Power Management. Overridden dynamically by operational profiles.
    powerManagement.enable = true;
    
    # Strictly false for desktop deployments. Target: Laptops (Optimus/Prime) only.
    powerManagement.finegrained = false;

    # GUI Settings toolkit
    nvidiaSettings = true;
  };

  # ── Global Environment Variables (Wayland Enforcement) ───────────────────
  # Applied globally during boot rather than session-init to guarantee stability 
  # for early-loading compositor components. SINGLE SOURCE OF TRUTH.
  environment.variables = {
    # Mandatory compositor bridge for NVIDIA native Wayland
    GBM_BACKEND                  = "nvidia-drm";
    
    # Force Vulkan/OpenGL to map exclusively to the NVIDIA ICD
    __GLX_VENDOR_LIBRARY_NAME    = "nvidia";
    
    # Enforce Hardware video decoding paths
    LIBVA_DRIVER_NAME            = "nvidia";

    # Electron/Chromium Native Wayland Hinting (VSCode, Discord, Obsidian)
    NIXOS_OZONE_WL               = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";

    # Toolkit Overrides (Qt, SDL, GTK) -> Default to Wayland
    QT_QPA_PLATFORM              = "wayland";
    SDL_VIDEODRIVER              = "wayland";
    GDK_BACKEND                  = "wayland,x11"; # Explicit fallback mapping
    
    MOZ_ENABLE_WAYLAND           = "1";

    # EGL Vendor Pathing mapped to the active Nix store generation
    __EGL_VENDOR_LIBRARY_DIRS    = "/run/opengl-driver/share/glvnd/egl_vendor.d";
  };

  # ── Stage-1 Kernel Module Injection (initrd) ─────────────────────────────
  # Note: Retained as commented. Injecting NVIDIA modules in initrd accelerates 
  # the first frame draw of the DM, but incurs a ~2s penalty during Stage-1. 
  # Deferring module load to user-space is preferred for faster TTY access.
  # boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
}
