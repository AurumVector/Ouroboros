# =============================================================================
# modules/profiles/llm/default.nix — Local LLM Inference Node (Ollama + CUDA)
# =============================================================================
# ARCHITECTURE OBJECTIVE:
#   Maximize tensor inference throughput for large-parameter LLMs locally on an 
#   NVIDIA RTX 4070 (12GB VRAM), without relying on external APIs.
#
# VRAM CAPACITY MATRIX (RTX 4070 12GB):
#   ┌─────────────────────┬──────────────┬───────────────────┐
#   │ Model Target        │ Quantization │ VRAM Footprint    │
#   ├─────────────────────┼──────────────┼───────────────────┤
#   │ Qwen2.5-7B          │ Q4_K_M       │ ~4.5 GB  ✓ Total  │
#   │ Qwen2.5-14B         │ Q4_K_M       │ ~8.5 GB  ✓ Total  │
#   │ Qwen2.5-32B         │ Q4_K_M       │ ~19 GB   ✗ Offload│
#   │ DeepSeek-R1-14B     │ Q4_K_M       │ ~8.5 GB  ✓ Total  │
#   │ Llama3.1-8B         │ Q8_0         │ ~8.5 GB  ✓ Total  │
#   │ Gemma2-9B           │ Q4_K_M       │ ~5.5 GB  ✓ Total  │
#   └─────────────────────┴──────────────┴───────────────────┘
#
# HARDWARE OPTIMIZATIONS:
#   - Flash Attention 2 (FA2): Reduces KV cache VRAM footprint by ~30%, allowing 
#     14B models to retain a 16K context window entirely within 12GB.
#   - Hugepages: 1GB statically allocated (512x2MB) to eliminate TLB misses 
#     during tensor transfers across the PCIe bus.
#   - Split-Storage: Model blobs (~GBs) are offloaded to the Level 1 SATA SSD 
#     to preserve Level 0 NVMe IOPS for the base OS.
# =============================================================================

{ config, pkgs, lib, ... }:

{
  # ── Memory Subsystem Overrides (CUDA Optimizaton) ────────────────────────
  # Statically allocate 512 2MB Hugepages (1GB total) for large tensor buffers.
  boot.kernel.sysctl = {
    "vm.nr_hugepages"            = lib.mkForce 512;
    "vm.nr_overcommit_hugepages" = lib.mkForce 4096;
  };

  # Enforce Transparent Hugepages globally for memory-intensive inference workloads
  boot.kernelParams = lib.mkAfter [ "transparent_hugepage=always" ];

  # ── Ollama Local Inference Engine ────────────────────────────────────────
  services.ollama = {
    enable       = true;
    package = pkgs.ollama-cuda;
    
    # OPSEC/Architecture: Offload heavy model blobs to the SATA SSD tier
    home         = "/mnt/models/ollama";

    environmentVariables = {
      # Concurrency: Restrict to 1 active request to maximize single-stream throughput
      OLLAMA_NUM_PARALLEL      = "1";

      # VRAM Efficiency: Enable Flash Attention 2
      OLLAMA_FLASH_ATTENTION   = "1";

      # Compositor Allowance: Restrict Wayland overhead to 512MB (freeing ~11.5GB)
      OLLAMA_GPU_OVERHEAD      = "536870912";

      # Baseline Context Window (Adjustable via ~/.ollama/config)
      OLLAMA_CONTEXT_LENGTH    = "8192";

      # OPSEC: Strict localhost binding to prevent lateral network access
      OLLAMA_HOST              = "127.0.0.1:11434";

      # Cache: Retain model in VRAM for 10 minutes post-query to eliminate cold starts
      OLLAMA_KEEP_ALIVE        = "10m";

      # Hardware Targeting: Bind exclusively to the primary Ada Lovelace GPU
      CUDA_VISIBLE_DEVICES     = "0";
      OLLAMA_MAX_LOADED_MODELS = "1";
    };
  };

  # ── Systemd Daemon Hardening & Resource Control ──────────────────────────
  systemd.services.ollama = {
    serviceConfig = {
      # Memory Throttling (Assuming 32GB RAM Base):
      # MemoryHigh engages soft-throttling; MemoryMax triggers the OOM killer.
      MemoryHigh       = "24G";
      MemoryMax        = "28G";
      MemoryAccounting = true;

      # Process Isolation
      ProtectSystem    = "strict";
      PrivateTmp       = true;
      NoNewPrivileges  = true;

      # Process Scheduling Priority (Negative = Higher Priority)
      Nice                 = -5;
      IOSchedulingClass    = "best-effort";
      IOSchedulingPriority = 0;
    };
  };

  # ── Disabling Unnecessary Overhead Workloads ─────────────────────────────
  programs.steam.enable     = lib.mkForce false;
  programs.gamemode.enable  = lib.mkForce false;

  # ── Inference & Development Toolchain ────────────────────────────────────
  environment.systemPackages = with pkgs; [
    ollama
    
    # Python environment mapped for API interaction and script orchestration
    (python3.withPackages (ps: with ps; [
      requests httpx numpy jupyter notebook
    ]))
  ];

  # ── LLM Environment Variables ────────────────────────────────────────────
  environment.sessionVariables = {
    PYTHONHISTFILE = "/persist/home/.python_history";
  };
}
