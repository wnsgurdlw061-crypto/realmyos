#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
UnifiedArch AI Runtime CLI

Usage:
  ai run <model>
  ai bench
  ai env switch <cuda12|rocm|cpu>

Examples:
  ai run llama3
  ai bench
  ai env switch cuda12
USAGE
}

detect_gpu_backend() {
  if lspci 2>/dev/null | grep -qi 'NVIDIA'; then
    echo cuda12
  elif lspci 2>/dev/null | grep -Eqi 'AMD|Radeon'; then
    echo rocm
  else
    echo cpu
  fi
}

cmd_run() {
  local model="${1:-}"
  [[ -n "$model" ]] || { echo "model is required"; exit 1; }

  local backend
  backend="$(detect_gpu_backend)"
  echo "[AI] backend: $backend"

  if command -v ollama >/dev/null 2>&1; then
    OLLAMA_NUM_GPU=1 ollama run "$model"
  else
    echo "[INFO] ollama not installed. Install it to run local LLMs." >&2
    exit 2
  fi
}

cmd_bench() {
  echo "[AI] running quick benchmark..."
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
  elif command -v rocminfo >/dev/null 2>&1; then
    rocminfo | head -n 40
  else
    lscpu | head -n 20
  fi
}

cmd_env_switch() {
  local target="${1:-}"
  [[ -n "$target" ]] || { echo "target env is required"; exit 1; }
  case "$target" in
    cuda12|rocm|cpu)
      sudo install -d /etc/unifiedarch
      echo "AI_RUNTIME=$target" | sudo tee /etc/unifiedarch/ai-runtime.env >/dev/null
      echo "[AI] runtime switched to: $target"
      ;;
    *)
      echo "unsupported env: $target"; exit 1 ;;
  esac
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    run) shift; cmd_run "$@" ;;
    bench) shift; cmd_bench "$@" ;;
    env)
      shift
      [[ "${1:-}" == "switch" ]] || { usage; exit 1; }
      shift
      cmd_env_switch "$@"
      ;;
    -h|--help|help|"") usage ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
