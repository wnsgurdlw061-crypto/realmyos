#!/bin/bash
# 수동 ISO 생성 스크립트

set -euo pipefail

ISO_DIR="/home/me/문서/os/build/unifiedarch-iso"
OUTPUT_DIR="/home/me/문서/os/build/output"

mkdir -p "$OUTPUT_DIR"

# 기본 파일 시스템 생성
echo "기본 파일 시스템 생성 중..."
mkdir -p "$ISO_DIR"/{boot,EFI/LiveOS,LiveOS}

# 부트로더 설정
echo "부트로더 설정 중..."
cat > "$ISO_DIR/boot/grub.cfg" << 'EOF'
set default=0
set timeout=10

menuentry "UnifiedArch OS" {
    linux /boot/vmlinuz
    initrd /boot/initrd
}
EOF

# EFI 부트로더
echo "EFI 부트로더 설정 중..."
mkdir -p "$ISO_DIR/EFI/BOOT"
cat > "$ISO_DIR/EFI/BOOT/BOOTX64.EFI" << 'EOF'
# EFI 스텁 (실제로는 더 복잡한 바이너리 필요)
EOF

# squashfs 파일 시스템 생성
echo "squashfs 생성 중..."
mksquashfs / "$OUTPUT_DIR/unifiedarch.squashfs" -e /proc -e /sys -e /dev -e /run -e /tmp

# ISO 생성
echo "ISO 생성 중..."
xorrisofs -o "$OUTPUT_DIR/unifiedarch-1.0.0.iso" \
    -b boot/grub.cfg \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e EFI/BOOT/BOOTX64.EFI \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    "$ISO_DIR"

echo "ISO 생성 완료: $OUTPUT_DIR/unifiedarch-1.0.0.iso"
