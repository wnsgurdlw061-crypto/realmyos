#!/usr/bin/env bash
set -euo pipefail

TOOLSET_FILE="${1:-config/toolsets/ai-arch-extra-tools.txt}"
TARGET_FILE="${2:-build/iso/profile/packages.x86_64}"

[[ -f "$TOOLSET_FILE" ]] || { echo "missing toolset file: $TOOLSET_FILE"; exit 1; }
[[ -f "$TARGET_FILE" ]] || { echo "missing target packages file: $TARGET_FILE"; exit 1; }

awk 'NF && $1 !~ /^#/' "$TOOLSET_FILE" | sort -u > /tmp/unifiedarch-toolset.lst
cp "$TARGET_FILE" /tmp/unifiedarch-base.lst
cat /tmp/unifiedarch-base.lst /tmp/unifiedarch-toolset.lst | awk 'NF' | sort -u > "$TARGET_FILE"

echo "[OK] merged $(wc -l < /tmp/unifiedarch-toolset.lst) packages into $TARGET_FILE"
