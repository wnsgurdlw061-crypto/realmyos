#!/bin/bash
#
# UnifiedArch OS Boot Configuration Manager
# 부트 체인 설정 및 관리 스크립트
#
# 기능:
# - UEFI/BIOS 이중 지원
# - GRUB 기본, systemd-boot 선택 가능
# - Secure Boot 지원
# - 복구 모드 자동 설정
#

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BOOT_DIR="/boot"
EFI_DIR="/boot/efi"
GRUB_DIR="$BOOT_DIR/grub"
SYSTEMD_BOOT_DIR="$EFI_DIR/systemd"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${PURPLE}[STEP]${NC} $1"; }

# 부트 모드 감지
detect_boot_mode() {
    log_step "부트 모드 감지 중..."
    
    if [[ -d "/sys/firmware/efi" ]]; then
        echo "UEFI"
        log_info "UEFI 부트 모드 감지됨"
    else
        echo "BIOS"
        log_info "BIOS 부트 모드 감지됨"
    fi
}

# Secure Boot 확인
check_secure_boot() {
    log_step "Secure Boot 상태 확인 중..."
    
    if [[ -d "/sys/firmware/efi" ]]; then
        if command -v mokutil &>/dev/null; then
            if mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
                echo "enabled"
                log_info "Secure Boot 활성화됨"
            else
                echo "disabled"
                log_info "Secure Boot 비활성화됨"
            fi
        else
            echo "unknown"
            log_warning "Secure Boot 상태 확인 불가"
        fi
    else
        echo "not_applicable"
        log_info "BIOS 모드 - Secure Boot 적용 불가"
    fi
}

# GRUB 설정
setup_grub() {
    local boot_mode="$1"
    local secure_boot="$2"
    
    log_step "GRUB 부트로더 설정 중..."
    
    # GRUB 패키지 설치 확인
    if ! command -v grub-install &>/dev/null; then
        log_error "GRUB이 설치되지 않았습니다"
        return 1
    fi
    
    # GRUB 설정 파일 생성
    mkdir -p "$GRUB_DIR"
    
    # 기본 GRUB 설정
    cat > /etc/default/grub << 'EOF'
# UnifiedArch OS GRUB Configuration

# 그래픽 설정
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="UnifiedArch"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 udev.log_level=3"
GRUB_CMDLINE_LINUX=""

# 그래픽 모드
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_TERMINAL_OUTPUT=gfxterm

# UEFI 설정
if [ "${grub_platform}" == "efi" ]; then
    GRUB_RECORDFAIL_TIMEOUT=0
    GRUB_DISABLE_SUBMENU=y
fi

# 보안 설정
GRUB_DISABLE_RECOVERY=false
GRUB_DISABLE_OS_PROBER=false

# 성능 최적화
GRUB_PRELOAD_MODULES="part_gpt part_msdos ext2 btrfs xfs"
GRUB_TIMEOUT_STYLE=menu

# 고급 기능
GRUB_SAVEDEFAULT=true
GRUB_ENABLE_CRYPTODISK=y
EOF
    
    # UEFI 모드 추가 설정
    if [[ "$boot_mode" == "UEFI" ]]; then
        cat >> /etc/default/grub << 'EOF'

# UEFI 전용 설정
GRUB_EARLY_INITRD="intel-ucode.img amd-ucode.img"
EOF
    fi
    
    # GRUB 스크립트 생성
    mkdir -p "$GRUB_DIR/custom"
    
    # UnifiedArch 고유 메뉴
    cat > "$GRUB_DIR/custom/40_unifiedarch" << 'EOF'
#!/bin/sh
exec tail -n +3 $0
# UnifiedArch OS 커스텀 부트 메뉴

# 복구 모드
menuentry "UnifiedArch OS (Recovery Mode)" {
    recordfail
    load_video
    gfxmode $linux_gfx_mode
    insmod gzio
    if [ x$grub_platform = xx86_efi ]; then
        insmod efi_gop
        insmod efi_uga
    fi
    insmod part_gpt
    insmod ext2
    set root='hd0,gpt2'
    if [ x$feature_platform_search_hint = xy ]; then
        search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gpt2 --hint-efi=hd0,gpt2 --hint-baremetal=ahci0,gpt2  UUID
    else
        search --no-floppy --fs-uuid --set=root UUID
    fi
    linux   /boot/vmlinuz-linux root=UUID=UUID ro recovery nomodeset
    initrd  /boot/initramfs-linux.img
}

# 메모리 테스트
menuentry "Memory Test (memtest86+)" {
    linux16 /boot/memtest86+.bin
}

# 펌웨어 설정
menuentry "UEFI Firmware Settings" {
    fwsetup
}

# 시스템 종료
menuentry "System Shutdown" {
    halt
}

# 시스템 재시작
menuentry "System Restart" {
    reboot
}
EOF
    
    chmod +x "$GRUB_DIR/custom/40_unifiedarch"
    
    log_success "GRUB 설정 완료"
}

# systemd-boot 설정
setup_systemd_boot() {
    log_step "systemd-boot 설정 중..."
    
    if [[ ! -d "/sys/firmware/efi" ]]; then
        log_error "systemd-boot는 UEFI 시스템만 지원합니다"
        return 1
    fi
    
    # EFI 파티션 마운트 확인
    if ! mountpoint -q "$EFI_DIR"; then
        log_error "EFI 파티션이 마운트되지 않았습니다"
        return 1
    fi
    
    # systemd-boot 설치
    bootctl --path="$EFI_DIR" install
    
    # 기본 부트로더 설정
    cat > "$EFI_DIR/loader/loader.conf" << 'EOF'
default unifiedarch.conf
timeout 5
console-mode max
editor yes
auto-firmware yes
EOF
    
    # 부트 엔트리 생성
    mkdir -p "$EFI_DIR/loader/entries"
    
    cat > "$EFI_DIR/loader/entries/unifiedarch.conf" << 'EOF'
title   UnifiedArch OS
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=ROOT_UUID rw quiet splash loglevel=3
EOF
    
    cat > "$EFI_DIR/loader/entries/unifiedarch-fallback.conf" << 'EOF'
title   UnifiedArch OS (Fallback)
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options root=UUID=ROOT_UUID rw quiet splash loglevel=3
EOF
    
    cat > "$EFI_DIR/loader/entries/unifiedarch-recovery.conf" << 'EOF'
title   UnifiedArch OS (Recovery)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=ROOT_UUID rw recovery nomodeset systemd.unit=rescue.target
EOF
    
    log_success "systemd-boot 설정 완료"
}

# Secure Boot 설정
setup_secure_boot() {
    local boot_mode="$1"
    
    log_step "Secure Boot 설정 중..."
    
    if [[ "$boot_mode" != "UEFI" ]]; then
        log_info "BIOS 모드 - Secure Boot 설정 건너뜀"
        return 0
    fi
    
    # MOK (Machine Owner Key) 생성
    if command -v mokutil &>/dev/null; then
        log_info "MOK 키 생성 중..."
        
        # 개인 키 생성
        if [[ ! -f "/var/lib/shim-signed/mok/MOK.priv" ]]; then
            openssl req -new -x509 -newkey rsa:2048 \
                -keyout /var/lib/shim-signed/mok/MOK.priv \
                -out /var/lib/shim-signed/mok/MOK.der \
                -nodes -days 36500 \
                -subj "/CN=UnifiedArch OS MOK/" 2>/dev/null || {
                log_warning "MOK 키 생성 실패"
                return 1
            }
        fi
        
        # 키 등록
        mokutil --import /var/lib/shim-signed/mok/MOK.der 2>/dev/null || {
            log_warning "MOK 키 등록 실패 (재부팅 후 필요)"
        }
        
        log_success "Secure Boot 설정 완료 (재부팅 후 MOK 등록 필요)"
    else
        log_warning "mokutil이 설치되지 않음"
    fi
}

# 복구 모드 설정
setup_recovery_mode() {
    log_step "복구 모드 설정 중..."
    
    # 복구 커널 파라미터 설정
    mkdir -p /etc/systemd/system/rescue.service.d
    
    cat > /etc/systemd/system/rescue.service.d/unifiedarch.conf << 'EOF'
[Service]
# 복구 모드에서 네트워크 활성화
Environment=SYSTEMD_SULOGIN_FORCE=1
ExecStartPre=/usr/bin/systemctl start NetworkManager.service
ExecStartPre=/usr/bin/systemctl start systemd-resolved.service

# 복구 스크립트 실행
ExecStartPre=/usr/local/bin/unifiedarch-recovery-setup
EOF
    
    # 복구 스크립트
    cat > /usr/local/bin/unifiedarch-recovery-setup << 'EOF'
#!/bin/bash
# UnifiedArch OS 복구 모드 설정 스크립트

echo "========================================="
echo "  UnifiedArch OS Recovery Mode"
echo "========================================="
echo ""
echo "시스템 상태:"
echo "  부팅 모드: $(detect_boot_mode)"
echo "  커널: $(uname -r)"
echo "  루트 파일시스템: $(findmnt -n -o FSTYPE /)"
echo ""
echo "사용 가능한 명령어:"
echo "  fsck -f /dev/sdaX     - 파일시스템 검사"
echo "  journalctl -p err    - 오류 로그"
echo "  systemctl status      - 서비스 상태"
echo "  networkctl status     - 네트워크 상태"
echo ""
echo "시스템 복구를 위해 root 암호를 설정하세요"
echo "========================================="
EOF
    
    chmod +x /usr/local/bin/unifiedarch-recovery-setup
    
    # emergency 모드 설정
    mkdir -p /etc/systemd/system/emergency.service.d
    
    cat > /etc/systemd/system/emergency.service.d/unifiedarch.conf << 'EOF'
[Service]
Environment=SYSTEMD_EMERGENCY_SERVICE=1
ExecStartPre=/usr/local/bin/unifiedarch-emergency-setup
EOF
    
    cat > /usr/local/bin/unifiedarch-emergency-setup << 'EOF'
#!/bin/bash
# UnifiedArch OS Emergency 모드 설정

echo "========================================="
echo "  UnifiedArch OS Emergency Mode"
echo "========================================="
echo ""
echo "심각한 시스템 오류가 발생했습니다"
echo "파일시스템을 검사하고 시스템을 복구하세요"
echo ""
echo "즉시 실행할 명령어:"
echo "  mount -o remount,rw /"
echo "  fsck -f /dev/sdaX"
echo "  journalctl -p err -b"
echo "========================================="
EOF
    
    chmod +x /usr/local/bin/unifiedarch-emergency-setup
    
    log_success "복구 모드 설정 완료"
}

# 부트로더 설치
install_bootloader() {
    local boot_mode="$1"
    local bootloader="$2"
    local target_disk="${3:-}"
    
    log_step "부트로더 설치 중..."
    
    case "$bootloader" in
        "grub")
            if [[ "$boot_mode" == "UEFI" ]]; then
                if [[ -n "$target_disk" ]]; then
                    grub-install --target=x86_64-efi --efi-directory="$EFI_DIR" \
                        --bootloader-id=unifiedarch --recheck --no-nvram
                    efibootmgr -c -d "$target_disk" -p 1 -L "UnifiedArch OS" -l "\\EFI\\unifiedarch\\grubx64.efi"
                else
                    grub-install --target=x86_64-efi --efi-directory="$EFI_DIR" \
                        --bootloader-id=unifiedarch --recheck
                fi
            else
                if [[ -n "$target_disk" ]]; then
                    grub-install --target=i386-pc --recheck "$target_disk"
                else
                    log_error "BIOS 모드에서는 타겟 디스크가 필요합니다"
                    return 1
                fi
            fi
            ;;
        "systemd-boot")
            if [[ "$boot_mode" == "UEFI" ]]; then
                bootctl --path="$EFI_DIR" update
            else
                log_error "systemd-boot는 UEFI만 지원합니다"
                return 1
            fi
            ;;
        *)
            log_error "알 수 없는 부트로더: $bootloader"
            return 1
            ;;
    esac
    
    log_success "부트로더 설치 완료"
}

# GRUB 설정 업데이트
update_grub_config() {
    log_step "GRUB 설정 업데이트 중..."
    
    if command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o "$GRUB_DIR/grub.cfg"
        log_success "GRUB 설정 업데이트 완료"
    else
        log_error "grub-mkconfig를 찾을 수 없습니다"
        return 1
    fi
}

# 부트 정보 표시
show_boot_info() {
    echo ""
    echo "========================================="
    echo "  UnifiedArch OS Boot Information"
    echo "========================================="
    echo ""
    echo "부트 모드: $(detect_boot_mode)"
    echo "Secure Boot: $(check_secure_boot)"
    echo ""
    echo "부트로더 상태:"
    
    if [[ -f "$GRUB_DIR/grub.cfg" ]]; then
        echo "  GRUB: 설치됨"
        echo "  설정 파일: $GRUB_DIR/grub.cfg"
    else
        echo "  GRUB: 미설치"
    fi
    
    if [[ -f "$EFI_DIR/loader/loader.conf" ]]; then
        echo "  systemd-boot: 설치됨"
        echo "  설정 파일: $EFI_DIR/loader/loader.conf"
    else
        echo "  systemd-boot: 미설치"
    fi
    
    echo ""
    echo "EFI 파티션:"
    if mountpoint -q "$EFI_DIR"; then
        echo "  마운트됨: $EFI_DIR"
        echo "  크기: $(df -h "$EFI_DIR" | tail -n1 | awk '{print $2}')"
    else
        echo "  마운트되지 않음"
    fi
    
    echo ""
    echo "부트 엔트리:"
    if [[ -f "$GRUB_DIR/grub.cfg" ]]; then
        echo "  GRUB 메뉴 항목: $(grep -c "^menuentry" "$GRUB_DIR/grub.cfg")개"
    fi
    
    if [[ -d "$EFI_DIR/loader/entries" ]]; then
        echo "  systemd-boot 엔트리: $(ls -1 "$EFI_DIR/loader/entries" | wc -l)개"
    fi
    
    echo "========================================="
}

# 도움말
show_help() {
    echo "UnifiedArch OS Boot Configuration Manager"
    echo ""
    echo "사용법: $0 [명령어] [옵션]"
    echo ""
    echo "명령어:"
    echo "  setup-grub          - GRUB 설정"
    echo "  setup-systemd-boot  - systemd-boot 설정"
    echo "  setup-secure-boot   - Secure Boot 설정"
    echo "  setup-recovery      - 복구 모드 설정"
    echo "  install            - 부트로더 설치"
    echo "  update-grub        - GRUB 설정 업데이트"
    echo "  info               - 부트 정보 표시"
    echo "  help               - 이 도움말"
    echo ""
    echo "옵션:"
    echo "  --bootloader TYPE  - 부트로더 타입 (grub|systemd-boot)"
    echo "  --disk DEVICE      - 타겟 디스크 (BIOS 모드 필수)"
    echo ""
    echo "예시:"
    echo "  $0 setup-grub"
    echo "  $0 install --bootloader grub --disk /dev/sda"
    echo "  $0 info"
}

# 메인 함수
main() {
    local action="${1:-info}"
    local bootloader="grub"
    local target_disk=""
    
    # 인자 파싱
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bootloader)
                bootloader="$2"
                shift 2
                ;;
            --disk)
                target_disk="$2"
                shift 2
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "루트 권한이 필요합니다"
        exit 1
    fi
    
    local boot_mode=$(detect_boot_mode)
    local secure_boot=$(check_secure_boot)
    
    case "$action" in
        setup-grub)
            setup_grub "$boot_mode" "$secure_boot"
            ;;
        setup-systemd-boot)
            setup_systemd_boot
            ;;
        setup-secure-boot)
            setup_secure_boot "$boot_mode"
            ;;
        setup-recovery)
            setup_recovery_mode
            ;;
        install)
            install_bootloader "$boot_mode" "$bootloader" "$target_disk"
            update_grub_config
            ;;
        update-grub)
            update_grub_config
            ;;
        info)
            show_boot_info
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            log_error "알 수 없는 명령어: $action"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
