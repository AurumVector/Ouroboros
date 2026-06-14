# =============================================================================
# modules/core/network.nix — Networking, Cryptographic DNS & RF OPSEC
# =============================================================================
# ARCHITECTURE OVERVIEW:
#   Manages network connectivity, domain name resolution, and radio frequency  
#   (RF) attack surface mitigation for the Ouroboros workstation.
#
# SECURE RESOLUTION DOCTRINE:
#   DNS queries are routed through systemd-resolved using Quad9 (providing  
#   upstream malware/phishing blocking). DNS-over-TLS (DoT) is strictly  
#   enforced to prevent ISP profiling and Man-in-the-Middle (MitM) attacks.
#   Legacy broadcast protocols (LLMNR) are explicitly disabled to prevent  
#   local network poisoning.
# =============================================================================

{ ... }:

{
  networking.networkmanager = {
    enable = true;
    # Prevent physical device tracking across different wireless networks
    wifi.macAddress = "random";
  };

  # ── Cryptographic DNS (systemd-resolved) ─────────────────────────────────
  services.resolved = {
    enable = true;

    settings = {
      Resolve = {   
        # DNSSEC enabled to verify cryptographic signatures of DNS records
        DNSSEC = "allow-downgrade";
        # Route all domains through this resolver
        Domains = "~.";
        # Strict DoT: Fail closed if TLS connection cannot be established
        DNSOverTLS = "yes";
        # Disable LLMNR to mitigate local network spoofing (e.g., Responder attacks)
        LLMNR = "false";
        MulticastDNS = "false";
        # Quad9 Primary (Malware blocking) / Quad9 IPv6
        FallbackDNS = "9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net";
      };
    };
  };

  # ── Radio Frequency (RF) OPSEC ───────────────────────────────────────────
  hardware.bluetooth = {
    enable       = true;
    # Disable Bluetooth radio on boot to eliminate broadcasting attack surface
    powerOnBoot  = false;
  };
   
  services.blueman.enable = true;
}
