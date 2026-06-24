# =============================================================================
# hosts/ouroboros/default.nix — Master Host Orchestrator
# =============================================================================
# ARCHITECTURE OVERVIEW:
#   This is the entry point for the Ouroboros bare-metal configuration.
#   It implements a strict separation of concerns, importing isolated
#   modules rather than declaring inline logic. 
#
# STATE MANAGEMENT:
#   system.stateVersion is strictly pinned to 26.05 to ensure declarative 
#   reproducibility across state migrations and prevent rollback failures.
#
# BOOT-TIME SPECIALISATIONS:
#   Ouroboros leverages NixOS specialisations to generate discrete boot
#   entries via Lanzaboote (Secure Boot). This allows dynamic allocation
#   of hardware resources and environment isolation depending on the 
#   selected operational profile (e.g., CyberLab vs. Mining) without 
#   cross-contamination of services.
# =============================================================================

{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware.nix

    # ── Core System Layer ──────────────────────────────────────
    ../../modules/core/boot.nix
    ../../modules/core/filesystem.nix
    ../../modules/core/locale.nix
    ../../modules/core/network.nix
    ../../modules/core/security.nix
    ../../modules/core/users.nix

    # ── Hardware Abstraction Layer ─────────────────────────────
    ../../modules/hardware/cpu.nix
    ../../modules/hardware/gpu.nix
    ../../modules/hardware/memory.nix
    ../../modules/hardware/storage.nix

    # ── User Space & Desktop ───────────────────────────────────
    ../../modules/desktop/plasma6.nix
  ];

  # ── Host Identity ────────────────────────────────────────────
  networking.hostName = "ouroboros";
  system.stateVersion = "26.05"; 

  # ── Peripherals Pipeline (OpenRazer) ─────────────────────────────────────
  # Hardware driver for Basilisk V3 Pro, Huntsman V2 TKL, and Mouse Dock Pro
  hardware.openrazer.enable = true;
  hardware.openrazer.users = [ "goldenhat" ]; # <-- REEMPLAZA ESTO POR TU USERNAME
  users.users.goldenhat.extraGroups = [ "plugdev" "input" "openrazer" ];
  boot.kernelModules = [ "razerkbd" "razermouse" "razeraccessory" "razerkraken" ];

  # ── Isolated Operational Profiles ────────────────────────────
  specialisation = {
    gaming.configuration = {
      imports = [ ../../modules/profiles/gaming ];
    };
    
    llm.configuration = {
      imports = [ ../../modules/profiles/llm ];
    };
    
    money.configuration = {
      imports = [ ../../modules/profiles/money ];
    };
    
    cyberlab.configuration = {
      imports = [ ../../modules/profiles/cyberlab ];
    };
  };
}
