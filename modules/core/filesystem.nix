# ==============================================================================
# SYSTEM LAYER: CORE (Inviolable System Base)
# MODULE:       modules/core/filesystem.nix
# PROJECT:      Ouroboros (NixOS 26.05 "Yarara")
# ARCHITECT:    aurumvector
# LICENSE:      MIT
# ==============================================================================
#
# ARCHITECTURAL DESIGN SCHEMATIC:
#
# Primary Drive (Samsung 990 Pro 1TB - PCIe 4.0)
# └── LUKS2 Container (Argon2id, AES-XTS 512-bit)
#     └── Btrfs Filesystem
#         ├── @           --> /           (Ephemeral Root - Reset on boot)
#         ├── @blank      -->             (Reference snapshot for clean rollback)
#         ├── @nix        --> /nix        (Persistent Nix Store)
#         ├── @persist    --> /persist    (Explicitly whitelisted system state)
#         ├── @home       --> /home       (User home directories)
#         └── @snapshots  --> /.snapshots (System-level recovery points)
#
# Dedicated Wear-Offloader (Crucial SATA SSD 256GB)
# └── LUKS2 Container (Argon2id, AES-XTS 512-bit)
#     └── Btrfs Filesystem
#         └── @ollama     --> /mnt/models (High-write weight: LLMs & Cache)
#
# Isolate Lab Drive (Sabrent NVMe 512GB)
# └── Mounted dynamically via "cyberlab" specialisation (Zero host contamination)
#
# Deep Storage Unit (HDD 2TB)
# └── XFS Volume          --> /mnt/storage (Cold Archive / Backups)
#
# ==============================================================================

{ config, lib, pkgs, ... }:

let
  # Import abstracted physical hardware constants (UUIDs & Disk IDs) [1]
  ids = import ../../lib/hardware-ids.nix;
in
{
  # ----------------------------------------------------------------------------
  # STAGE-1 DEVICE INITIALIZATION (systemd-initrd)
  # ----------------------------------------------------------------------------
  # NixOS 26.05 "Yarara" defaults to systemd-stage-1.
  # Cryptographic unlock and rollback engines run natively on systemd.[2]
  boot.initrd.systemd.enable = lib.mkDefault true;

  # ----------------------------------------------------------------------------
  # LUKS2 DECRYPTION DEFAULTS & TOKENS
  # ----------------------------------------------------------------------------
  
  # Cryptroot: Primary Samsung 990 Pro [1]
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/${ids.uuids.luksNvmeMain}";
    
    # Read raw 4096-byte key from USB Key (Slot 1) [1]
    keyFile = "/dev/disk/by-id/${ids.byId.usbKey}";
    keyFileSize = 4096;
    keyFileOffset = 0;

    # Safe fallback window: if USB key is absent, request passphrase in 30s [1]
    crypttabExtraOpts = [ "keyfile-timeout=30" "nofail" ];

    # Low-Latency SSD Tuning
    allowDiscards = true;    # Passthrough TRIM commands down to NVMe controller [1]
    bypassWorkqueues = true; # Direct physical I/O bypass; eliminates CPU scheduler queue latency
  };

  # Cryptmodels: Secondary Crucial SATA SSD (Ollama Datasets) [1]
  boot.initrd.luks.devices."cryptmodels" = {
    device = "/dev/disk/by-uuid/${ids.uuids.luksSataSsd}";
    
    # Detached token unlocking (Slot 1) synced with primary key
    keyFile = "/dev/disk/by-id/${ids.byId.usbKey}";
    keyFileSize = 4096;
    keyFileOffset = 0;
    
    # Fallback and stability opts; prevents system hangs if secondary bus is slow
    crypttabExtraOpts = [ "keyfile-timeout=30" "nofail" ];
    allowDiscards = true;
  };

  # ----------------------------------------------------------------------------
  # FILE SYSTEM MOUNT MATRIX (DECLARATIVE)
  # ----------------------------------------------------------------------------
  # Mount options explanations:
  # - compress=zstd:3: Default Btrfs balance. Optimal space saving / CPU ratio.[1]
  # - compress=zstd:1: Lower compression for highly uncompressible weights (saves CPU).[1]
  # - noatime: Prevents write wear on NAND cells on read operations.[1]
  # - discard=async: Asynchronous block freeing; avoids I/O blocking during deletions.[1]
  
  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
  };

  fileSystems."/persist" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@persist" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
    neededForBoot = true; # Critical: Impermanence state-engine mount phase [1]
  };

  fileSystems."/home" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
  };

  fileSystems."/.snapshots" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@snapshots" "compress=zstd:3" "noatime" "space_cache=v2" "discard=async" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/${ids.uuids.efiPartition}";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" "iocharset=utf8" ]; # Secure mask: Root-only readable
  };

  # Dedicated high-wear Ollama Models and Podman Storage Cache [1]
  # Offloads write amplification away from primary Samsung 990 Pro.
  # Write Amplification Factor (WAF) formula: $WAF = \frac{\text{Flash Writes}}{\text{Host Writes}}$
  fileSystems."/mnt/models" = {
    device = "/dev/mapper/cryptmodels";
    fsType = "btrfs";
    options = [ "subvol=@ollama" "compress=zstd:1" "noatime" "space_cache=v2" "discard=async" "nofail" ];
  };

  # Cold Storage mechanical vault [1]
  fileSystems."/mnt/storage" = {
    device = "/dev/disk/by-uuid/${ids.uuids.hddStorage}";
    fsType = "xfs";
    options = [ "noatime" "nofail" "lazytime" ]; # lazytime merges inode writes; preserves mechanical head lifespan
  };

  # ----------------------------------------------------------------------------
  # EPHEMERAL ROOT ROLLBACK ENGINE (STATELESS RESET)
  # ----------------------------------------------------------------------------
  # WARN: The automatic rollback is commented out under Phase 1 of Ouroboros.
  # Safe promotion to Phase 2 requires ensuring the '@blank' template snapshot
  # is stable and populated correctly on target disk.[1]
  #
  # Temporal systemd initrd execution path:
  # systemd-cryptsetup@cryptroot.service --> rollback-root.service --> sysroot.mount [3]

  /*
  boot.initrd.systemd.services.rollback-root = {
    description = "Btrfs Stateless Rollback: Erase @ and restore from @blank";
    wantedBy = [ "initrd.target" ];
    after = [ "systemd-cryptsetup@cryptroot.service" ];
    before = [ "sysroot.mount" ];

    unitConfig.DefaultDependencies = "no";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      mkdir -p /mnt
      mount -t btrfs -o subvol=/ /dev/mapper/cryptroot /mnt

      # Recursively parse and destroy any nested subvolumes created during session
      if btrfs subvolume show /mnt/@ &>/dev/null; then
        while IFS= read -r sv; do
          [ -n "$sv" ] && btrfs subvolume delete "/mnt/$sv" || true
        done < <(btrfs subvolume list -o /mnt/@ | awk '{print $NF}' | sort -r)

        # Obliterate active corrupted root
        btrfs subvolume delete /mnt/@
      fi

      # Clone a sterile runtime environment from template
      btrfs subvolume snapshot /mnt/@blank /mnt/@
      umount /mnt
    '';
  };
  */

  # ----------------------------------------------------------------------------
  # EXPLICIT PERSISTENCE LAYER (Impermanence)
  # ----------------------------------------------------------------------------
  # Enforces a declarative data footprint. Any path omitted here is wiped.
  # Symlinks are mounted from `/persist` directly onto the ephemeral `/`.[1]
 environment.persistence."/persist" = {
  hideMounts = true;
  directories = [
    "/var/lib/nixos"
    "/var/lib/prometheus"

    # High-Security Vaults
    { directory = "/persist/secureboot"; mode = "0700"; } # Lanzaboote keys
    { directory = "/persist/secrets";    mode = "0700"; } # Cryptographic agenix secrets
    { directory = "/persist/mining";     mode = "0700"; } # Cold wallets

    # Ollama configuration
    { directory = "/var/lib/ollama";     mode = "0750"; }
  ];

  files = [
      # SSH Host Keys (Persisted to maintain known host fingerprints) [1]
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
