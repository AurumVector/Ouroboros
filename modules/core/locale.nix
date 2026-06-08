# =============================================================================
# modules/core/locale.nix — Regionalization, Time & Console Environment
# =============================================================================
# ARCHITECTURE OVERVIEW:
#   Configures the localization layer for the Ouroboros workstation.
#
# FORENSIC & OPSEC CONSIDERATIONS:
#   While the primary user environment is set to Spanish (es_ES.UTF-8), 
#   system messages (LC_MESSAGES) are strictly forced to English (en_US.UTF-8).
#   This ensures that kernel panics, systemd logs, and audit trails remain 
#   universally searchable and parsable by automated threat-hunting tools.
#
# TIME SYNCHRONIZATION:
#   Accurate timekeeping is critical for cryptographic operations (e.g., DNSSEC, 
#   TLS certificate validation, Kerberos). systemd-timesyncd is enabled to 
#   maintain strict NTP synchronization.
# =============================================================================

{ pkgs, ... }:

{
  # ── Time & Synchronization ───────────────────────────────────────────────
  time.timeZone = "Europe/Madrid";
  
  # Ensure strict time synchronization for cryptographic validity
  services.timesyncd = {
    enable = true;
  };

  # ── System Localization ──────────────────────────────────────────────────
  i18n = {
    defaultLocale = "es_ES.UTF-8";
    
    extraLocaleSettings = {
      LC_ADDRESS        = "es_ES.UTF-8";
      LC_IDENTIFICATION = "es_ES.UTF-8";
      LC_MEASUREMENT    = "es_ES.UTF-8";
      LC_MONETARY       = "es_ES.UTF-8";
      LC_NAME           = "es_ES.UTF-8";
      LC_NUMERIC        = "es_ES.UTF-8";
      LC_PAPER          = "es_ES.UTF-8";
      LC_TELEPHONE      = "es_ES.UTF-8";
      LC_TIME           = "es_ES.UTF-8";
      
      # FORCE English for system messages to preserve standardized log parsing
      LC_MESSAGES       = "en_US.UTF-8"; 
    };
  };

  # ── TTY Environment (Bare-metal console) ─────────────────────────────────
  # Configures the pre-GUI terminal environment. 
  # Uses Terminus 24pt for enhanced legibility on high-DPI displays.
  console = {
    font     = "ter-v24n";
    keyMap   = "es";
    packages = [ pkgs.terminus_font ];
  };
}
