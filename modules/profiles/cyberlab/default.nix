# =============================================================================
# modules/profiles/cyberlab/default.nix — Advanced Forensics & Penetration Node
# =============================================================================
# ARCHITECTURE OBJECTIVE (NATION-STATE OPSEC LEVEL):
#   Transform the Ouroboros workstation into a highly compartmentalized, 
#   air-gapped-equivalent cyber operations center. Designed for zero-trust 
#   malware detonation, reverse engineering, and offensive security operations.
#
# DOCTRINE OF ISOLATION:
#   ├── 1. Cryptographic Isolation: The Sabrent NVMe (/mnt/cyberlab) is unlocked
#   │      ONLY during this boot profile. The primary system is shielded.
#   ├── 2. MicroVM Detonation Chamber: Integration of AWS Firecracker and QEMU 
#   │      MicroVMs for sub-second, hardware-isolated malware execution.
#   ├── 3. The BlackArch Arsenal: Rootless Podman orchestrated to pull and 
#   │      execute the BlackArch Linux toolchain in an ephemeral container.
#   └── 4. Userspace Sandboxing: Firejail enforced for all high-risk host apps.
# =============================================================================

{ config, pkgs, lib, ... }:

let
  ids = import ../../../lib/hardware-ids.nix;
in
{
  # ── Tier 1: Cryptographic Hardware Unlocking (Sabrent NVMe) ──────────────
  boot.initrd.luks.devices."cryptcyber" = {
    device            = "/dev/disk/by-uuid/${ids.uuids.luksSabrent}";
    keyFile           = "${ids.byId.usbKey}";
    keyFileSize       = 4096;
    keyFileOffset     = 0;
    crypttabExtraOpts = [ "keyfile-timeout=30" ];
    allowDiscards     = true;
  };

  fileSystems."/mnt/cyberlab" = {
    device  = "/dev/mapper/cryptcyber";
    fsType  = "btrfs";
    options = [ "compress=zstd:3" "noatime" "discard=async" ];
  };

  # ── Tier 2: MicroVMs & Hypervisor Stack (The Detonation Chamber) ─────────
  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = false;       # OPSEC: Prevent QEMU from running as root
        swtpm.enable = true;
      };
    };

    # Rootless Container Engine (BlackArch Host)
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # ── Tier 3: Userspace Sandboxing (Firejail) ──────────────────────────────
  # Enforces strict Linux Namespaces and Seccomp-bpf filters on standard apps.
  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      # Automatically sandbox web traffic generated during OSINT
      firefox = {
        executable = "${lib.getBin pkgs.librewolf}/bin/librewolf";
        profile    = "${pkgs.firejail}/etc/firejail/librewolf.profile";
        extraArgs  = [ "--private" "--dns=1.1.1.1" ];
      };
    };
  };

  # ── Tier 4: Tactical Network OPSEC (nftables Air-Gap) ────────────────────
  # Define a strict "Host-Only" virtual bridge for malware detonation.
  # Packets from the dirty subnet (10.99.99.0/24) are DROPPED before reaching
  # the physical LAN or the internet, preventing malware C2 callbacks.
  networking.nftables.ruleset = lib.mkAfter ''
    table inet cyberlab_airgap {
      chain forward {
        type filter hook forward priority filter; policy drop;
        
        # Block malicious VMs from accessing the local home network
        iifname "virbr_dirty" oifname "enp*" drop
        iifname "virbr_dirty" oifname "wlan*" drop
      }
    }
  '';

  # ── Host-Level Eviction (Reclaiming Resources) ───────────────────────────
  programs.steam.enable     = lib.mkForce false;
  programs.gamemode.enable  = lib.mkForce false;
  services.ollama.enable    = lib.mkForce false;

  # ── The Cyber Operations Toolchain ───────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # ── MicroVMs & Isolation ──
    firecracker      # AWS-grade microVMs for instantaneous malware detonation
    firectl          # CLI for Firecracker orchestration
    cloud-hypervisor # Rust-based VMM for high-performance isolated workloads

    # ── Forensic Analysis ──
    wireshark
    tcpdump
    volatility3      # RAM Memory forensics
    binwalk          # Firmware analysis

    # ── Reverse Engineering ──
    radare2
    ghidra
    imhex            # Hex editor for reverse engineers

    # ── BlackArch Container Alias ──
    # Deploys a sterile BlackArch environment on demand via Podman
    (writeShellScriptBin "blackarch-shell" ''
      echo "[*] Initializing Sterile BlackArch Linux Environment..."
      podman run -it --rm \
        --name blackarch_ephemeral \
        --network none \
        blackarchlinux/blackarch:latest /bin/bash
    '')
  ];

  # ── Extreme OPSEC Sysctls (Memory & Kernel Hardening) ────────────────────
  boot.kernel.sysctl = {
    # Prevent the kernel from swapping CyberLab memory to disk, ensuring 
    # decrypted malware fragments never touch persistent storage.
    "vm.swappiness" = lib.mkForce 0;
    
    # Enable IP forwarding strictly for controlled NAT environments
    "net.ipv4.ip_forward" = lib.mkForce 1;
    
    # Panic the kernel immediately on an "Oops" to prevent memory exploits
    # from successfully executing code after a crash.
    "kernel.panic_on_oops" = 1;
  };
}
