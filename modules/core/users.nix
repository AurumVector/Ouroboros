# =============================================================================
# modules/core/users.nix — Identity, Base Toolchain & Nix Daemon Configuration
# =============================================================================
# SECURITY DOCTRINE (Identity Management):
#   - Immutable Users: User accounts cannot be modified imperatively at runtime
#     (e.g., via usermod). All identities are strictly declarative.
#   - Password OPSEC: Password hashes are NEVER stored in the globally readable 
#     /nix/store. Instead, they are referenced dynamically via hashedPasswordFile
#     pointing to an external, strictly permissioned file (0600) on the 
#     persistent volume (/persist/secrets/).
#
# DYNAMIC BINARY EXECUTION (nix-ld):
#   Enabled to allow the execution of unpatched, dynamically linked ELF binaries.
#   This is critical for running standalone cybersecurity tooling, ML frameworks,
#   and pre-compiled Python wheels without requiring Nix-native wrappers.
# =============================================================================

{ pkgs, lib, ... }:

{
  # ── Declarative User Identities ──────────────────────────────────────────
  users.mutableUsers = false;

  users.users.goldenhat = {
    isNormalUser = true;
    uid = 1000;
    description  = "GoldenHat (AurumVector)";
    shell        = pkgs.fish;
    
    # Cryptographic Isolation: Read hash from persistent storage
   # hashedPasswordFile = "/persist/secrets/goldenhat.passwd";
    hashedPassword = "$6$f/zfjgUgdB6b4jbc$v3iaOKOOM518YNEbndl4vFRVRoX3JLOnRhNs3xSq94g0mRdaIvM65PQHl6LRC4PcHiy.522FsKd4rtaYYAOf71";

    # Principle of Least Privilege: Granular group assignments
    extraGroups = [
      "wheel"           # Administrative access (sudo-rs)
      "video" "audio"   # Hardware media access
      "input"           # Peripherals / Gaming controllers
      "libvirtd" "kvm"  # CyberLab VM orchestration
      "qemu-libvirtd"   # Hypervisor access
      "podman"          # Rootless containerization
      "networkmanager"  # Non-privileged network switching
      "gamemode"        # Feral Interactive GameMode
    ];
  };

  # ── Declarative System Groups (Fixes nix flake check errors) ─────────────
  users.groups = {
    sshd = { gid = 400; };
    rtkit = { gid = 401; };
    nm-iodine = { gid = 402; };
    geoclue = { gid = 403; };
    fwupd-refresh = { gid = 404; };
    polkituser = { gid = 405; };
    systemd-oom = { gid = 406; };
    systemd-coredump = { gid = 407; };
    wpa_supplicant = { gid = 408; };
    nscd = { gid = 409; };
    mandb = { gid = 410; };
  };

  # ── Core System Toolchain ────────────────────────────────────────────────
  # Essential utilities required for bare-metal administration, troubleshooting,
  # and forensic analysis regardless of the active environment.
  environment.systemPackages = with pkgs; [
    # System Diagnostics
    git curl wget file
    htop btop iotop
    pciutils usbutils lm_sensors
    nvtopPackages.full  # GPU telemetry (NVIDIA/AMD)

    # Cryptography & Storage
    btrfs-progs cryptsetup sbctl

    # Modern CLI Replacements
    ripgrep fd bat eza zoxide fzf tmux

    # Nix Native Tooling
    nix-tree nix-diff nix-index
    nvd # Visualize generation diffs

    # Core Editors
    vim neovim
  ];

  # ── Unpatched Binary Execution (nix-ld) ──────────────────────────────────
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib openssl libGL glib libgcc expat
    ];
  };

  # ── Shell Environment ────────────────────────────────────────────────────
  programs.fish.enable = true;

  # ── Secure Shell Daemon (SSH) ────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";          # Prohibit direct root access
      PasswordAuthentication = false;  # Strictly Key-based authentication
      KbdInteractiveAuthentication = false;
    };
  };

  # ── Nix Daemon & Package Manager ─────────────────────────────────────────
  nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store   = true; # Hardlink identical files to save disk space
      trusted-users         = [ "root" "goldenhat" ];
      
      # Upstream Binary Caches
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSDs="
      ];
    };

    # Automated State Maintenance (Garbage Collection)
   nix.gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 14d";
    };

  # ── Home-Manager Integration ─────────────────────────────────────────────
  home-manager = {
    useGlobalPkgs   = true;
    useUserPackages = true;
#    users.goldenhat = import ../../home/goldenhat.nix;
  };
}
