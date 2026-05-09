#!/usr/bin/env bash
set -euo pipefail

# Auto-select runtime profile during install or first boot
if lspci | grep -qi 'NVIDIA'; then
  profile="cuda12"
elif lspci | grep -Eqi 'AMD|Radeon'; then
  profile="rocm"
else
  profile="cpu"
fi

install -d /etc/unifiedarch
echo "AI_RUNTIME=$profile" > /etc/unifiedarch/ai-runtime.env

echo "[Installer] selected AI runtime profile: $profile"
