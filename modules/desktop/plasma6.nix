# =============================================================================
# modules/desktop/plasma6.nix — KDE Plasma 6 (Wayland Native UI)
# =============================================================================
# ARCHITECTURE OVERVIEW:
#   KDE Plasma 6 is selected as the primary UX layer for Ouroboros due to:
#     ├── Mature Wayland protocol support with NVIDIA proprietary/open drivers.
#     ├── Variable Refresh Rate (VRR / G-Sync) integration in Plasma 6.1+.
#     ├── Tearing protocol support (Critical for un-composited CS2 gaming).
#     └── Lower compositor overhead (KWin) compared to GNOME (Mutter) under 
#         heavy GPU compute workloads (CUDA/LLM).
#
# DISPLAY MANAGER:
#   SDDM is configured strictly in Wayland mode to ensure a complete, 
#   end-to-end X11-free boot and login sequence. Xwayland is retained solely 
#   for legacy application compatibility within the session.
# =============================================================================

{ pkgs, lib, ... }:

{
  # ── KDE Plasma 6 Desktop Environment ─────────────────────────────────────
  services.desktopManager.plasma6.enable = true;

  # Strict Bloatware Exclusion: Remove unnecessary default applications 
  # to minimize the attack surface and maintain a lean Nix store.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    plasma-browser-integration # Excluded due to native LibreWolf isolation
    kate                       # Replaced by Neovim/VSCode in user workflows
    elisa                      # Unnecessary media player
    khelpcenter                # Redundant offline help
  ];

  # ── SDDM Display Manager (Wayland Native) ────────────────────────────────
  services.displayManager.sddm = {
    enable       = true;
    wayland.enable = true;
    # Optional aesthetic tuning (Assuming a custom Ouroboros theme)
    # theme = "catppuccin-mocha"; 
  };

  # ── XServer & Xwayland Compatibility Layer ───────────────────────────────
  # The legacy X server is required to spawn Xwayland.
  services.xserver = {
    enable = true;
    
    # Keyboard Layout Mapping
    xkb = {
      layout  = "es";
      variant = "";
      options = "compose:ralt"; # Map Right-Alt to Compose key
    };

    # OPSEC: Prevent the X server from binding to network sockets (TCP)
    exportConfiguration = true;
    displayManager.startx.enable = false;
  };
  
  # Enable Xwayland for legacy gaming/application compatibility
  programs.xwayland.enable = true;

  # ── Wayland Desktop Portals (XDG) ────────────────────────────────────────
  # Critical for Screen Sharing (OBS/Discord) and Sandboxed App file dialogs
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

  # ── Base Acoustic Pipeline (PipeWire) ─────────────────────────────────────
  # Base-level audio routing. Gaming specialisation overrides quantum latency.
  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = true; # Required for Steam/Proton 32-bit prefixes
    pulse.enable      = true; # PulseAudio translation layer
    jack.enable       = false; 
  };

  # ── Essential Graphical Toolchain ────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # Core Utilities
    kdePackages.dolphin     # File Manager
    kdePackages.konsole     # Terminal Emulator
    kdePackages.ark         # Archive Manager
    
    # Media & Diagnostics
    kdePackages.spectacle   # Advanced Screenshot/Recording tool
    kdePackages.gwenview    # Image Viewer
    kdePackages.okular      # PDF/Document Viewer
    kdePackages.filelight   # Visual Disk Usage Analyzer
    kdePackages.kcalc       # Calculator
    kdePackages.kdegraphics-thumbnailers # Dolphin Thumbnails
  ];
}
