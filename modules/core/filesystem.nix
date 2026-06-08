# =============================================================================
# modules/core/filesystem.nix — Cryptographic Storage & Ephemeral Root
# =============================================================================
# ARCHITECTURE BLUEPRINT:
#
#   Primary Forge (Samsung 990 Pro 1TB - PCIe 4.0)
#     └── LUKS2 (Argon2id, AES-XTS 512-bit) ← Stage-1 Detached USB Key Unlock
#           └── Btrfs
#                 ├── @           → /           (Ephemeral Root)
#                 ├── @blank      → Reference snapshot for stateless rollback
#                 ├── @nix        → /nix        (Persistent Nix store)
#                 ├── @persist    → /persist    (Explicit state persistence)
#                 ├── @home       → /home       (User data)
#                 └── @snapshots  → /.snapshots (System recovery points)
#
#   Secondary Storage
#     ├── Sabrent NVMe 512GB → CyberLab isolated storage (Active via specialisation)
#     └── HDD 2TB            → /mnt/storage (XFS data volume)
#
# IMPERMANENCE DOCTRINE (Stateless System):
#   The root (/) subvolume is destroyed and recreated from the sterile @blank 
#   snapshot on every boot cycle. Only explicitly whitelisted directories in 
#   environment.persistence (symlinked from /persist) survive a reboot.
# =============================================================================

{ config, lib, pkgs, ... }:

let
  # Inherit abstracted hardware identifiers (UUIDs/by-id)
  ids = import ../../lib/hardware-ids.nix;
in
{
  # ── LUKS2 Cryptography: Stage-1 USB Key Unlocking ────────────────────────
  # High-entropy raw keyfile (4096 bytes) read directly from block device.
  # Fallback to manual passphrase (Slot 0) if USB key is absent for 30s.
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/${ids.uuids.luksNvmeMain}";

    keyFile       = "${ids.byId.usbKey}";
    keyFileSize   = 4096;
    keyFileOffset = 0;
    
    crypttabExtraOpts = [ "keyfile-timeout=30" ];

    # Low-latency NVMe tuning
    allowDiscards = true;       # Enables TRIM across LUKS layer
    bypassWorkqueues = true;    # Direct I/O bypass for max NVMe IOPS
  };
  
  # ── LUKS2: 256GB SATA (Ollama + Podman Store) ──────────
  boot.initrd.luks.devices."cryptmodels" = {
    device            = "/dev/disk/by-uuid/${ids.uuids.luksSataSsd}";
    keyFile           = "${ids.byId.usbKey}";
    keyFileSize       = 4096;
    keyFileOffset     = 0;
    crypttabExtraOpts = [ "keyfile-timeout=30" ];
    allowDiscards     = true; 
  };

  # ── Btrfs Subvolume Declarations ─────────────────────────────────────────
  # Standardized Options:
  #   - compress=zstd:3: Optimal balance between compression ratio and CPU load.
  #   - noatime / space_cache=v2 / discard=async: SSD longevity and performance.
  fileSystems."/" = {
    device  = "/dev/mapper/cryptroot";
    fsType  = "btrfs";
    options = [ "subvol=@" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
  };

  fileSystems."/nix" = {
    device  = "/dev/mapper/cryptroot";
    fsType  = "btrfs";
    options = [ "subvol=@nix" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
  };

  fileSystems."/persist" = {
    device        = "/dev/mapper/cryptroot";
    fsType        = "btrfs";
    options       = [ "subvol=@persist" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
    neededForBoot = true; # Mandatory for Impermanence to stitch state in initrd
  };

  fileSystems."/home" = {
    device  = "/dev/mapper/cryptroot";
    fsType  = "btrfs";
    options = [ "subvol=@home" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
  };

  fileSystems."/.snapshots" = {
    device  = "/dev/mapper/cryptroot";
    fsType  = "btrfs";
    options = [ "subvol=@snapshots" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
  };

  fileSystems."/boot" = {
    device  = "/dev/disk/by-uuid/${ids.uuids.efiPartition}";
    fsType  = "vfat";
    options = [ "fmask=0077" "dmask=0077" "iocharset=utf8" ];
  };

  fileSystems."/mnt/storage" = {
    device  = "/dev/disk/by-uuid/${ids.uuids.hddStorage}";
    fsType  = "xfs";
    options = [ "noatime" "nofail" "lazytime" ]; # nofail prevents boot hang if HDD is disconnected
  };

  # ── Ephemeral Root Rollback Engine ───────────────────────────────────────
  # Executes in initrd before root is mounted. Annihilates the previous session's
  # root state and clones a pristine root from the @blank snapshot.
  # ── Mount: SATA SSD Models & Container Store ───────────────────────────
  fileSystems."/mnt/models" = {
    device  = "/dev/mapper/cryptmodels";
    fsType  = "btrfs";
    # zstd:1 enough for compressed models, saving CPU cycles
    options = [ "subvol=@ollama" "compress=zstd:1" "noatime" "discard=async" ];
  };
  boot.initrd.systemd.services.rollback-root = {
    description = "Btrfs Stateless Rollback: Erase @ and restore from @blank";
    wantedBy    = [ "initrd.target" ];
    after       = [ "systemd-cryptsetup@cryptroot.service" ];
    before      = [ "sysroot.mount" ];
    
    unitConfig.DefaultDependencies = "no";
    
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      set -euo pipefail

      mkdir -p /mnt
      mount -t btrfs -o subvol=/ /dev/mapper/cryptroot /mnt

      # Recursively delete any nested subvolumes created during the session
      if btrfs subvolume show /mnt/@ &>/dev/null; then
        while IFS= read -r sv; do
          [ -n "$sv" ] && btrfs subvolume delete "/mnt/$sv" || true
        done < <(btrfs subvolume list -o /mnt/@ | awk '{print $NF}' | sort -r)
        
        # Destroy the main root subvolume
        btrfs subvolume delete /mnt/@
      fi

      # Clone a sterile root from the reference snapshot
      btrfs subvolume snapshot /mnt/@blank /mnt/@
      umount /mnt
    '';
  };

  # ── Declarative State Persistence (Impermanence) ─────────────────────────
  # Defines the strict whitelist of files/directories allowed to persist 
  # across the stateless root wipes.
  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      # Core System State
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/bluetooth"
      "/var/lib/NetworkManager"

      # Workload Profiles (Persisted regardless of active specialisation)
      "/var/lib/libvirt"    # CyberLab VMs
      "/var/lib/prometheus" # Monitoring Telemetry

      # High-Security / Sensitive Paths
      { directory = "/var/lib/ollama"; mode = "0750"; }
      { directory = "/persist/secureboot"; mode = "0700"; }
      { directory = "/persist/secrets";    mode = "0700"; }
      { directory = "/persist/mining";     mode = "0700"; } # External mining config/wallets
    ];

    files = [
      "/etc/machine-id" # Maintains consistent network identity
      # SSH Host Keys
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
