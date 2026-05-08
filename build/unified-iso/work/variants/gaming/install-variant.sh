#!/bin/bash
# Variant-specific installation script
set -euo pipefail

VARIANT_NAME="$(basename "$(dirname "$0")")"
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

log_info "Installing UnifiedArch OS $VARIANT_NAME variant..."

# 패키지 설치
if [[ -f "packages.x86_64" ]]; then
    log_info "Installing packages for $VARIANT_NAME..."
    pacman -Syu --noconfirm
    pacman -S --needed --noconfirm - < packages.x86_64
else
    log_error "Package list not found for $VARIANT_NAME"
    exit 1
fi

# 변형 버전별 설정 적용
case "$VARIANT_NAME" in
    "minimal")
        log_info "Applying minimal configuration..."
        systemctl disable NetworkManager || true
        systemctl enable dhcpcd || true
        ;;
    "enterprise")
        log_info "Applying enterprise configuration..."
        systemctl enable sshd || true
        systemctl enable fail2ban || true
        systemctl enable ufw || true
        ;;
    "gaming")
        log_info "Applying gaming configuration..."
        systemctl enable NetworkManager || true
        usermod -a -G input,audio,video,games,render $USER || true
        ;;
    "standard")
        log_info "Applying standard configuration..."
        systemctl enable NetworkManager || true
        systemctl enable gdm || true
        ;;
esac

log_success "$VARIANT_NAME variant installation completed!"
