#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="${PROFILE_DIR:-build/iso/profile}"
OUT_DIR="${OUT_DIR:-out}"
WORK_DIR="${WORK_DIR:-work}"
ISO_NAME="${ISO_NAME:-unifiedarch}"
ISO_LABEL="${ISO_LABEL:-UNIFIEDARCH_$(date +%Y%m)}"

if ! command -v mkarchiso >/dev/null 2>&1; then
  echo "[ERROR] mkarchiso not found. Install archiso package first." >&2
  exit 1
fi

if [[ ! -f "$PROFILE_DIR/packages.x86_64" ]]; then
  echo "[ERROR] missing package list: $PROFILE_DIR/packages.x86_64" >&2
  exit 1
fi

echo "[INFO] profile: $PROFILE_DIR"
echo "[INFO] output : $OUT_DIR"
echo "[INFO] work   : $WORK_DIR"

mkdir -p "$OUT_DIR" "$WORK_DIR"
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

ISO_PATH=$(find "$OUT_DIR" -maxdepth 1 -type f -name '*.iso' | head -n 1 || true)
if [[ -z "$ISO_PATH" ]]; then
  echo "[ERROR] ISO was not generated." >&2
  exit 1
fi

echo "[OK] ISO generated: $ISO_PATH"
