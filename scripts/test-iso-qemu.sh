#!/bin/bash
#
# UnifiedArch OS QEMU Test Script
# ISO 이미지를 QEMU 가상머신에서 테스트
#

set -euo pipefail

# ========== 설정 ==========
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build"
FINAL_DIR="${BUILD_DIR}/final"

# QEMU 설정
MEMORY="${MEMORY:-4096}"        # RAM (MB)
CPUS="${CPUS:-2}"               # CPU 코어 수
DISK_SIZE="${DISK_SIZE:-20G}"   # 테스트 디스크 크기

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ========== ISO 파일 찾기 ==========
find_iso() {
    local iso_file=$(find "$FINAL_DIR" -name "*.iso" -type f | head -n1)
    
    if [[ -z "$iso_file" ]]; then
        log_error "ISO 파일을 찾을 수 없습니다."
        log_info "먼저 ISO를 빌드하세요: sudo ./scripts/build-iso-fixed.sh"
        exit 1
    fi
    
    echo "$iso_file"
}

# ========== QEMU 확인 ==========
check_qemu() {
    if ! command -v qemu-system-x86_64 &>/dev/null; then
        log_error "QEMU가 설치되지 않았습니다."
        echo ""
        echo "설치 방법:"
        echo "  Arch: sudo pacman -S qemu-full"
        echo "  Ubuntu: sudo apt install qemu-system-x86"
        echo "  Fedora: sudo dnf install qemu-system-x86"
        exit 1
    fi
    
    # KVM 확인
    if [[ -e /dev/kvm ]]; then
        log_success "KVM 하드웨어 가속 사용 가능"
        KVM_OPT="-enable-kvm"
    else
        log_info "KVM 없이 실행 (느릴 수 있음)"
        KVM_OPT=""
    fi
}

# ========== 테스트 디스크 생성 ==========
create_test_disk() {
    local disk_file="${BUILD_DIR}/test-disk.qcow2"
    
    if [[ ! -f "$disk_file" ]]; then
        log_info "테스트 디스크 생성 중 (${DISK_SIZE})..."
        qemu-img create -f qcow2 "$disk_file" "$DISK_SIZE"
    fi
    
    echo "$disk_file"
}

# ========== 라이브 부팅 테스트 ==========
test_live_boot() {
    log_info "라이브 부팅 테스트 시작..."
    
    local iso_file=$(find_iso)
    log_info "ISO 파일: $iso_file"
    
    log_info "QEMU 시작 (종료: Ctrl+A, X)"
    echo ""
    
    qemu-system-x86_64 \
        $KVM_OPT \
        -m "$MEMORY" \
        -smp "$CPUS" \
        -cdrom "$iso_file" \
        -boot d \
        -vga virtio \
        -display gtk \
        -usb \
        -device usb-tablet \
        -net nic \
        -net user,hostfwd=tcp::2222-:22 \
        -audio-driver pa \
        -device intel-hda \
        -device hda-duplex
}

# ========== 설치 테스트 ==========
test_install() {
    log_info "설치 테스트 시작..."
    
    local iso_file=$(find_iso)
    local disk_file=$(create_test_disk)
    
    log_info "ISO 파일: $iso_file"
    log_info "테스트 디스크: $disk_file"
    
    log_info "QEMU 시작 (종료: Ctrl+A, X)"
    echo ""
    echo "설치 테스트 안내:"
    echo "  1. UnifiedArch OS가 부팅됩니다"
    echo "  2. 바탕화면의 'Install UnifiedArch OS' 아이콘 클릭"
    echo "  3. 설치 마법사 진행"
    echo "  4. 설치 완료 후 재부팅"
    echo ""
    
    qemu-system-x86_64 \
        $KVM_OPT \
        -m "$MEMORY" \
        -smp "$CPUS" \
        -cdrom "$iso_file" \
        -drive file="$disk_file",format=qcow2,if=virtio \
        -boot d \
        -vga virtio \
        -display gtk \
        -usb \
        -device usb-tablet \
        -net nic \
        -net user,hostfwd=tcp::2222-:22 \
        -audio-driver pa \
        -device intel-hda \
        -device hda-duplex
}

# ========== 설치된 시스템 부팅 ==========
test_installed() {
    log_info "설치된 시스템 부팅 테스트..."
    
    local disk_file="${BUILD_DIR}/test-disk.qcow2"
    
    if [[ ! -f "$disk_file" ]]; then
        log_error "테스트 디스크가 없습니다. 먼저 설치 테스트를 실행하세요."
        exit 1
    fi
    
    log_info "테스트 디스크: $disk_file"
    log_info "QEMU 시작 (종료: Ctrl+A, X)"
    echo ""
    
    qemu-system-x86_64 \
        $KVM_OPT \
        -m "$MEMORY" \
        -smp "$CPUS" \
        -drive file="$disk_file",format=qcow2,if=virtio \
        -vga virtio \
        -display gtk \
        -usb \
        -device usb-tablet \
        -net nic \
        -net user,hostfwd=tcp::2222-:22 \
        -audio-driver pa \
        -device intel-hda \
        -device hda-duplex
}

# ========== UEFI 부팅 테스트 ==========
test_uefi() {
    log_info "UEFI 부팅 테스트..."
    
    local iso_file=$(find_iso)
    local efi_vars="${BUILD_DIR}/efivars.fd"
    
    # OVMF 펌웨어 확인
    local ovmf_code=""
    local ovmf_vars=""
    
    for path in \
        "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd" \
        "/usr/share/OVMF/OVMF_CODE.fd" \
        "/usr/share/qemu/OVMF.fd"; do
        if [[ -f "$path" ]]; then
            ovmf_code="$path"
            break
        fi
    done
    
    for path in \
        "/usr/share/edk2-ovmf/x64/OVMF_VARS.fd" \
        "/usr/share/OVMF/OVMF_VARS.fd"; do
        if [[ -f "$path" ]]; then
            ovmf_vars="$path"
            break
        fi
    done
    
    if [[ -z "$ovmf_code" ]]; then
        log_error "OVMF 펌웨어를 찾을 수 없습니다."
        echo "설치: sudo pacman -S edk2-ovmf"
        exit 1
    fi
    
    # UEFI 변수 파일 복사
    cp "$ovmf_vars" "$efi_vars"
    
    log_info "ISO 파일: $iso_file"
    log_info "UEFI 펌웨어: $ovmf_code"
    log_info "QEMU 시작 (종료: Ctrl+A, X)"
    echo ""
    
    qemu-system-x86_64 \
        $KVM_OPT \
        -m "$MEMORY" \
        -smp "$CPUS" \
        -cdrom "$iso_file" \
        -boot d \
        -vga virtio \
        -display gtk \
        -usb \
        -device usb-tablet \
        -net nic \
        -net user \
        -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
        -drive if=pflash,format=raw,file="$efi_vars" \
        -audio-driver pa \
        -device intel-hda \
        -device hda-duplex
}

# ========== 도움말 ==========
show_help() {
    echo "UnifiedArch OS QEMU 테스트 스크립트"
    echo ""
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  live      - 라이브 부팅 테스트 (기본)"
    echo "  install   - 설치 테스트"
    echo "  installed - 설치된 시스템 부팅"
    echo "  uefi      - UEFI 부팅 테스트"
    echo "  help      - 이 도움말"
    echo ""
    echo "환경 변수:"
    echo "  MEMORY    - RAM 크기 (MB, 기본: 4096)"
    echo "  CPUS      - CPU 코어 수 (기본: 2)"
    echo "  DISK_SIZE - 테스트 디스크 크기 (기본: 20G)"
    echo ""
    echo "단축키:"
    echo "  Ctrl+A, X - QEMU 종료"
    echo "  Ctrl+A, C - QEMU 모니터"
}

# ========== 메인 ==========
main() {
    local action="${1:-live}"
    
    check_qemu
    
    case "$action" in
        live)
            test_live_boot
            ;;
        install)
            test_install
            ;;
        installed)
            test_installed
            ;;
        uefi)
            test_uefi
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            log_error "알 수 없는 옵션: $action"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
