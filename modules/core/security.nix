# =============================================================================
# modules/core/security.nix — Defensive Hardening & Kernel Telemetry
# =============================================================================
# DEFENSE-IN-DEPTH ARCHITECTURE:
#   ├── Privilege Escalation: sudo-rs (Rust implementation, memory-safe)
#   ├── Mandatory Access Control: AppArmor (Profile-based confinement)
#   ├── Kernel Telemetry: auditd (Execution, identity, and syscall tracking)
#   ├── Network Filtering: nftables (Stateful, default DROP policies)
#   └── Memory/Kernel Exploit Mitigation: sysctl hardening parameters
#
# NVIDIA COMPATIBILITY MATRICES:
#   ✗ lockdown=confidentiality → Breaks NVIDIA proprietary module injection.
#   ✓ lockdown=integrity       → Compatible (Blocks direct /dev/mem writes).
#   → Lockdown is intentionally deferred to allow unsigned driver loading, 
#     compensated by strict module loading tracking via auditd.
#
# SEPARATION OF CONCERNS:
#   → vm.* sysctl parameters (Performance) belong in modules/hardware/memory.nix.
#   → This module strictly enforces kernel.* and net.* security directives.
# =============================================================================

{ config, pkgs, lib, ... }:

{
  # ── Privilege Management (Memory-Safe) ───────────────────────────────────
  security.sudo-rs = {
    enable             = true;
    wheelNeedsPassword = true;
  };
  # Deprecate legacy C-based sudo to mitigate memory corruption vulnerabilities
  security.sudo.enable = false;

  # ── Mandatory Access Control (MAC) ───────────────────────────────────────
  security.apparmor = {
    enable = true;
    # Selective Enforcement: killUnconfinedConfinables is disabled to prevent 
    # disruption of unprofiled development workloads. Enforcement is applied
    # per-profile rather than globally.
    killUnconfinedConfinables = false;
    packages = [ pkgs.apparmor-profiles ];
  };

  # ── Kernel Audit Framework (Threat Hunting Telemetry) ────────────────────
  security.audit = {
    enable = true;
    rules  = [
      # Tactic: Execution Tracking (Log all spawned processes)
      "-a always,exit -F arch=b64 -S execve -k exec_tracking"
      
      # Tactic: Persistence/Credential Access (Monitor identity files)
      "-w /etc/passwd  -p wa -k identity_tampering"
      "-w /etc/shadow  -p wa -k identity_tampering"
      "-w /etc/group   -p wa -k identity_tampering"
      
      # Tactic: Privilege Escalation (Monitor sudoers modification)
      "-w /etc/sudoers -p wa -k privilege_escalation"
      "-w /etc/sudoers.d/ -p wa -k privilege_escalation"
      
      # Tactic: Discovery (Track permission denied events in sensitive dirs)
      "-a always,exit -F arch=b64 -S open -F dir=/etc -F success=0 -k access_denied"
      
      # Tactic: Defense Evasion (Monitor dynamic module loading)
      "-w /sbin/insmod  -p x -k module_load"
      "-w /sbin/modprobe -p x -k module_load"

      # Tactic: Impact (Monitor unauthorized mount operations)
      "-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k unauthorized_mount"
    ];
  };

  # ── Real-Time Priorities (Desktop/Gaming QoS) ────────────────────────────
  security.rtkit.enable = true;
  security.polkit.enable = true;

  # ── Network Hardening (nftables) ─────────────────────────────────────────
  networking.firewall.enable  = false; # Disable legacy iptables/xtables
  networking.nftables.enable  = true;
  networking.nftables.ruleset = ''
    table inet filter {
      chain input {
        type filter hook input priority filter; policy drop;

        iifname "lo" accept

        # Stateful inspection: Allow established/related, drop invalid
        ct state { established, related } accept
        ct state invalid drop

        # Anti-Flood ICMP limits
        icmp type echo-request limit rate 10/second accept
        icmpv6 type {
          echo-request, nd-neighbor-solicit,
          nd-router-advert, nd-neighbor-advert,
          mld-listener-query
        } accept
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
        # Routing logic (e.g., KVM/virbr) is injected here by specialisations
      }

      chain output {
        type filter hook output priority filter; policy accept;
      }
    }
  '';

  # ── Kernel Exploitation Mitigations (sysctl) ─────────────────────────────
  boot.kernel.sysctl = {
    # ── Memory & Execution Space Protection ──
    # Restrict unprivileged visibility of kernel pointers (KASLR leak prevention)
    "kernel.kptr_restrict"                = 2;
    # Restrict unprivileged access to kernel ring buffer (dmesg)
    "kernel.dmesg_restrict"               = 1;
    # Prevent unprivileged eBPF execution (Mitigates local privilege escalation)
    "kernel.unprivileged_bpf_disabled"    = 1;
    # Enable BPF JIT hardening (Blind constant injection attacks)
    "net.core.bpf_jit_harden"             = 2;
    # Yama LSM: Restrict ptrace to direct descendants only
    "kernel.yama.ptrace_scope"            = 1;
    # Restrict perf events to root to mitigate CPU side-channel leaks
    "kernel.perf_event_paranoid"          = 3;

    # ── Network Stack Hardening ──
    # Defend against TCP SYN flood attacks
    "net.ipv4.tcp_syncookies"             = 1;
    # Enforce Reverse Path Filtering to drop spoofed packets
    "net.ipv4.conf.all.rp_filter"         = 1;
    "net.ipv4.conf.default.rp_filter"     = 1;
    # Disable ICMP redirect acceptance (Mitigates routing-based MiTM)
    "net.ipv4.conf.all.accept_redirects"  = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects"  = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    # Do not send ICMP redirects
    "net.ipv4.conf.all.send_redirects"    = 0;
    
    # IP Forwarding explicitly disabled in base configuration
    "net.ipv4.ip_forward"                 = 0;
    "net.ipv6.conf.all.forwarding"        = 0;
    
    # TCP Hardening (Protect against TIME-WAIT assassination)
    "net.ipv4.tcp_rfc1337"                = 1;
    # Log martian packets (Packets with impossible addresses)
    "net.ipv4.conf.all.log_martians"      = 1;
  };
}
