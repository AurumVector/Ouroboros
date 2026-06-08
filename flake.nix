# =============================================================================
# OUROBOROS — Core System Flake
# Identity: AurumVector / GoldenHat
# Target: NixOS 26.05 Workstation (Secured / Declarative)
# =============================================================================
# Architecture Blueprint:
# flake.nix
#  ├── hosts/          # Machine-specific configurations (Ouroboros Core)
#  ├── modules/        # Reusable system modules (Hardening, Drivers, Core)
#  ├── home/           # User-space management via Home-Manager
#  └── lib/            # Custom Nix functions and helpers
# =============================================================================

{
  description = "Ouroboros - Sovereignty-focused NixOS Workstation Framework";

  inputs = {
    # Core Distribution Channels
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # User Space & Dotfiles Management
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hardware & Security Layer Integration
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Root Ephemerality & State Persistence Control
    impermanence = {
      url = "github:nix-community/impermanence";
    };
  };

  outputs = { self, nixpkgs, home-manager, lanzaboote, impermanence, ... }@inputs: {
    nixosConfigurations.ouroboros = nixpkgs.lib.nixosSystem {
      # Target Architecture
      system = "x86_64-linux";

      # Passes external inputs downstream to submodules for clean referencing
      specialArgs = {
        inherit inputs self;
      };

      modules = [
        # ── CRITICAL ARCHITECTURE FIX: Global Nixpkgs Config ───────────────
        # In a pure flake environment, nixpkgs configuration must be injected 
        # declaratively into the module system. This enables NVIDIA and 
        # proprietary firmware to compile without breaking purity.
        {
          nixpkgs.config.allowUnfree = true;
        }

        # ── Upstream Declarative Extensions ────────────────────────────────
        lanzaboote.nixosModules.lanzaboote
        impermanence.nixosModules.impermanence
        home-manager.nixosModules.home-manager

        # ── Master Host Definition ─────────────────────────────────────────
        ./hosts/ouroboros/default.nix
      ];
    };
  };
}
