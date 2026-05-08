#!/bin/bash
# UnifiedArch OS 통합 ISO 빌드 스크립트
# 4가지 변형 버전을 모두 포함하는 통합 ISO 생성

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
BUILD_DATE=$(date +%Y%m%d)
BUILD_ID="unifiedarch-unified-$VERSION-$BUILD_DATE"

# 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_ROOT/build"
UNIFIED_BUILD_DIR="$BUILD_DIR/unified-iso"
VARIANTS_DIR="$PROJECT_ROOT/variants"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 헬퍼 함수
banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 ____  _ _ _   _                     _      
| __ )(_) | | | | __ _ _ __   __ _ (_)_ __ 
|  _ \| | | |_| |/ _` | '_ \ / _` || | '_ \
| |_) | | |  _  | (_| | | | | (_| || | | | |
|____/|_|_|_| |_|\__,_|_| |_|\__,_||_|_| |_|
                                              
      통합 ISO 빌드 시스템 v1.0
    모든 변형 버전을 하나의 ISO로
EOF
    echo -e "${NC}"
}

# 빌드 환경 확인
check_build_environment() {
    log_step "통합 ISO 빌드 환경 확인 중..."
    
    # 필수 도구 확인
    local required_tools=("make" "gcc" "git" "tar" "gzip" "find" "xorriso" "mksquashfs")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "필수 도구를 찾을 수 없음: $tool"
            exit 1
        fi
    done
    
    # archiso 설치 확인
    if ! command -v mkarchiso >/dev/null 2>&1; then
        log_warning "archiso가 설치되지 않음. 수동 ISO 생성을 사용합니다."
    fi
    
    # 빌드 디렉토리 생성
    mkdir -p "$UNIFIED_BUILD_DIR"/{work,profiles,boot,isolinux}
    
    log_success "통합 ISO 빌드 환경 확인 완료"
}

# 변형 버전별 프로필 생성
create_variant_profiles() {
    log_step "변형 버전별 프로필 생성 중..."
    
    local variants=("standard" "minimal" "enterprise" "gaming")
    
    for variant in "${variants[@]}"; do
        log_info "변형 버전 프로필 생성: $variant"
        
        local profile_dir="$UNIFIED_BUILD_DIR/profiles/$variant"
        mkdir -p "$profile_dir"
        
        # 패키지 목록 복사
        if [[ -f "$VARIANTS_DIR/$variant/packages.x86_64" ]]; then
            cp "$VARIANTS_DIR/$variant/packages.x86_64" "$profile_dir/"
        else
            log_warning "패키지 목록을 찾을 수 없음: $variant"
        fi
        
        # 변형 버전별 설정 파일 생성
        cat > "$profile_dir/variant.conf" << EOF
# UnifiedArch OS $variant Variant Configuration
VARIANT_NAME="$variant"
VARIANT_DISPLAY_NAME="$(echo $variant | sed 's/\b\w/\u&/g')"
VARIANT_SIZE="$($VARIANTS_DIR/$variant/get_size.sh 2>/dev/null echo "Unknown")"
VARIANT_DESCRIPTION="$($VARIANTS_DIR/$variant/description.txt 2>/dev/null cat || echo "UnifiedArch OS $variant variant")"
EOF
        
        # 변형 버전별 설치 스크립트 생성
        cat > "$profile_dir/install-variant.sh" << 'EOF'
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
EOF
        
        chmod +x "$profile_dir/install-variant.sh"
    done
    
    log_success "변형 버전별 프로필 생성 완료"
}

# 통합 부트 메뉴 생성
create_boot_menu() {
    log_step "통합 부트 메뉴 생성 중..."
    
    # isolinux.cfg 생성
    cat > "$UNIFIED_BUILD_DIR/isolinux/isolinux.cfg" << 'EOF'
# UnifiedArch OS 통합 부트 메뉴
DEFAULT menu.c32
PROMPT 0
MENU TITLE UnifiedArch OS - 통합 설치 미디어
MENU BACKGROUND /boot/splash.png
MENU TIMEOUT 100
MENU ROWS 10
MENU TABMSGROW 15
MENU CMDLINEROW 15
MENU HELPMSGROW 17
MENU HELPMSGENDROW 25
MENU COLOR border 30;44 #40ffffff #a0000000 std
MENU COLOR title 1;36;44 #90ffffff #a0000000 std
MENU COLOR sel 7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel 37;44 #50ffffff #a0000000 std
MENU COLOR help 37;40 #c0ffffff #a0000000 std
MENU COLOR timeout_msg 37;40 #80ffffff #00000000 std
MENU COLOR timeout 1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07 37;40 #90ffffff #00000000 std

# 메인 메뉴
LABEL main
    MENU LABEL ^1. UnifiedArch OS 변형 버전 선택
    MENU DEFAULT
    COM32 bootmenu.c32
    APPEND /boot/menu.cfg

# 직접 부트 옵션
LABEL standard
    MENU LABEL ^2. Standard (2GB) - 모든 기능 포함
    KERNEL /boot/vmlinuz-linux
    APPEND initrd=/boot/initramfs-linux.img archisobasedir=arch archisolabel=UNIFIEDARCH variant=standard

LABEL minimal
    MENU LABEL ^3. Minimal (800MB) - 극단적 경량화
    KERNEL /boot/vmlinuz-linux
    APPEND initrd=/boot/initramfs-linux.img archisobasedir=arch archisolabel=UNIFIEDARCH variant=minimal

LABEL enterprise
    MENU LABEL ^4. Enterprise (3GB) - 서버 등급
    KERNEL /boot/vmlinuz-linux
    APPEND initrd=/boot/initramfs-linux.img archisobasedir=arch archisolabel=UNIFIEDARCH variant=enterprise

LABEL gaming
    MENU LABEL ^5. Gaming (4GB) - 게이밍 최적화
    KERNEL /boot/vmlinuz-linux-zen
    APPEND initrd=/boot/initramfs-linux-zen.img archisobasedir=arch archisolabel=UNIFIEDARCH variant=gaming

# 시스템 옵션
LABEL memtest
    MENU LABEL ^6. Memory Test (memtest86+)
    KERNEL /boot/memtest86+

LABEL reboot
    MENU LABEL ^7. Reboot System
    COM32 reboot.c32

LABEL poweroff
    MENU LABEL ^8. Power Off System
    COM32 poweroff.c32
EOF

    # 상세 메뉴 생성
    cat > "$UNIFIED_BUILD_DIR/boot/menu.cfg" << 'EOF'
# UnifiedArch OS 상세 메뉴
MENU TITLE UnifiedArch OS - 변형 버전 선택
MENU BACKGROUND /boot/splash.png
MENU TIMEOUT 60
MENU ROWS 12

LABEL standard
    MENU LABEL ^1. Standard (2GB) - 모든 기능 포함
    MENU DESC
    UnifiedArch OS Standard 버전입니다.
    - GNOME, KDE, XFCE, MATE, Cinnamon 데스크톱 환경
    - 개발 도구, 멀티미디어, 오피스 애플리케이션
    - 가상화, 게이밍 지원
    - 완전한 기능을 제공하는 표준 버전
    ENDTEXT
    KERNEL /boot/vmlinuz-linux
    APPEND initrd=/boot/initramfs-linux.img archisobasedir=arch archisolabel=UNIFIEDARCH variant=standard

LABEL minimal
    MENU LABEL ^2. Minimal (800MB) - 극단적 경량화
    MENU DESC
    UnifiedArch OS Minimal 버전입니다.
    - i3 창 관리자 기반의 최소한의 환경
    - 필수 시스템 도구만 포함
    - 빠른 부팅과 낮은 메모리 사용량
    - 서버나 최소한의 데스크톱 환경에 적합
    ENDTEXT
    KERNEL /boot/vmlinuz-linux
    APPEND initrd=/boot/initramfs-linux.img archisobasedir=arch archisolabel=UNIFIEDARCH variant=minimal

LABEL enterprise
    MENU LABEL ^3. Enterprise (3GB) - 서버 등급
    MENU DESC
    UnifiedArch OS Enterprise 버전입니다.
    - LTS 커널 기반의 안정적인 서버 환경
    - 데이터베이스, 컨테이너, 모니터링 도구
    - 보안 및 하드웨어 모니터링
    - 기업 환경에 최적화된 서버 등급
    ENDTEXT
    KERNEL /boot/vmlinuz-linux-lts
    APPEND initrd=/boot/initramfs-linux-lts.img archisobasedir=arch archisolabel=UNIFIEDARCH variant=enterprise

LABEL gaming
    MENU LABEL ^4. Gaming (4GB) - 게이밍 최적화
    MENU DESC
    UnifiedArch OS Gaming 버전입니다.
    - Zen 커널 기반의 게이밍 최적화
    - 최신 그래픽 드라이버와 Vulkan 지원
    - Steam, Lutris, Wine/Proton
    - 게이밍 퍼포먼스 최적화 도구
    ENDTEXT
    KERNEL /boot/vmlinuz-linux-zen
    APPEND initrd=/boot/initramfs-linux-zen.img archisobasedir=arch archisolabel=UNIFIEDARCH variant=gaming

LABEL back
    MENU LABEL ^5. 이전 메뉴로
    MENU EXIT
EOF

    log_success "통합 부트 메뉴 생성 완료"
}

# 통합 archiso 프로필 생성
create_unified_profile() {
    log_step "통합 archiso 프로필 생성 중..."
    
    cat > "$UNIFIED_BUILD_DIR/work/profiledef.sh" << EOF
#!/usr/bin/env bash
#
# UnifiedArch OS 통합 archiso 프로필

iso_name="unifiedarch-unified"
iso_label="UNIFIEDARCH"
iso_publisher="UnifiedArch OS Project"
iso_application="UnifiedArch OS Unified Live/Install - All Variants"
iso_version="$VERSION"
install_dir="unifiedarch"
work_dir="$UNIFIED_BUILD_DIR/work/archiso"
out_dir="$UNIFIED_BUILD_DIR/out"
bootmodes=("bios" "uefi")
arch="x86_64"
pacman_conf="pacman.conf"
EOF

    # 통합 패키지 목록 생성 (모든 변형 버전의 공통 패키지)
    cat > "$UNIFIED_BUILD_DIR/work/packages.x86_64" << 'EOF'
# UnifiedArch OS 통합 기본 패키지
# 모든 변형 버전에 공통적으로 필요한 패키지

# Base system
base
base-devel
linux
linux-zen
linux-lts
linux-firmware
linux-headers

# Installation tools
arch-install-scripts
pacman
curl
wget
git
vim
nano

# Network tools
networkmanager
network-manager-applet
wireless_tools
wpa_supplicant

# Display drivers (full support)
xf86-video-amdgpu
xf86-video-intel
xf86-video-nouveau
mesa
vulkan-radeon
vulkan-intel

# Boot loaders
grub
efibootmgr
refind

# File systems
dosfstools
ntfs-3g
exfat-utils
btrfs-progs
xfsprogs

# Compression utilities
tar
gzip
bzip2
xz
unzip
p7zip

# System utilities
htop
tree
jq
rsync

# Boot menu system
syslinux
isolinux
memtest86+

# UnifiedArch core packages
unifiedarch-installer
unifiedarch-kernel-modules
unifiedarch-config
EOF

    # pacman.conf 생성
    cat > "$UNIFIED_BUILD_DIR/work/pacman.conf" << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

# Repositories
[core]
SigLevel = PackageRequired
Include = /etc/pacman.d/mirrorlist

[extra]
SigLevel = PackageRequired
Include = /etc/pacman.d/mirrorlist

[community]
SigLevel = PackageRequired
Include = /etc/pacman.d/mirrorlist

[multilib]
SigLevel = PackageRequired
Include = /etc/pacman.d/mirrorlist
EOF

    log_success "통합 archiso 프로필 생성 완료"
}

# 변형 버전별 데이터 통합
integrate_variant_data() {
    log_step "변형 버전별 데이터 통합 중..."
    
    local variants=("standard" "minimal" "enterprise" "gaming")
    
    for variant in "${variants[@]}"; do
        log_info "변형 버전 데이터 통합: $variant"
        
        local variant_dir="$UNIFIED_BUILD_DIR/work/variants/$variant"
        mkdir -p "$variant_dir"
        
        # 패키지 목록 복사
        if [[ -f "$VARIANTS_DIR/$variant/packages.x86_64" ]]; then
            cp "$VARIANTS_DIR/$variant/packages.x86_64" "$variant_dir/"
        fi
        
        # 변형 버전별 설치 스크립트 복사
        if [[ -f "$UNIFIED_BUILD_DIR/profiles/$variant/install-variant.sh" ]]; then
            cp "$UNIFIED_BUILD_DIR/profiles/$variant/install-variant.sh" "$variant_dir/"
        fi
        
        # 변형 버전별 설정 파일 복사
        if [[ -f "$UNIFIED_BUILD_DIR/profiles/$variant/variant.conf" ]]; then
            cp "$UNIFIED_BUILD_DIR/profiles/$variant/variant.conf" "$variant_dir/"
        fi
    done
    
    # 통합 설치 스크립트 생성
    cat > "$UNIFIED_BUILD_DIR/work/unified-install.sh" << 'EOF'
#!/bin/bash
# UnifiedArch OS 통합 설치 스크립트
set -euo pipefail

VARIANT="${1:-standard}"
VARIANT_DIR="/run/archiso/variants/$VARIANT"

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }

log_info "UnifiedArch OS 설치 시작 - 변형 버전: $VARIANT"

# 변형 버전 확인
if [[ ! -d "$VARIANT_DIR" ]]; then
    log_error "변형 버전을 찾을 수 없음: $VARIANT"
    exit 1
fi

# 변형 버전별 설치 스크립트 실행
if [[ -f "$VARIANT_DIR/install-variant.sh" ]]; then
    cd "$VARIANT_DIR"
    bash install-variant.sh
    log_success "$VARIANT 변형 버전 설치 완료"
else
    log_error "설치 스크립트를 찾을 수 없음: $VARIANT_DIR/install-variant.sh"
    exit 1
fi
EOF
    
    chmod +x "$UNIFIED_BUILD_DIR/work/unified-install.sh"
    
    log_success "변형 버전별 데이터 통합 완료"
}

# ISO 이미지 생성
create_unified_iso() {
    log_step "통합 ISO 이미지 생성 중..."
    
    cd "$UNIFIED_BUILD_DIR/work"
    
    # archiso를 사용한 ISO 생성
    if command -v mkarchiso >/dev/null 2>&1; then
        log_info "archiso를 사용하여 ISO 생성 중..."
        
        # 기본 구조 생성
        mkdir -p airootfs/{usr/bin,etc,boot,variants}
        
        # 부트 메뉴 파일 복사
        cp -r "$UNIFIED_BUILD_DIR/boot" airootfs/
        cp -r "$UNIFIED_BUILD_DIR/isolinux" airootfs/
        
        # 변형 버전 데이터 복사
        cp -r "$UNIFIED_BUILD_DIR/work/variants" airootfs/
        
        # 통합 설치 스크립트 복사
        cp "$UNIFIED_BUILD_DIR/work/unified-install.sh" airootfs/usr/bin/
        
        # ISO 빌드
        if mkarchiso -v -w . -o "$UNIFIED_BUILD_DIR/out" .; then
            log_success "archiso ISO 생성 완료"
        else
            log_error "archiso ISO 생성 실패"
            return 1
        fi
    else
        log_warning "archiso가 없어 수동으로 ISO 생성 중..."
        
        # 수동 ISO 생성 (xorriso 사용)
        local iso_dir="$UNIFIED_BUILD_DIR/iso-content"
        mkdir -p "$iso_dir"
        
        # 부트 파일 복사
        cp -r "$UNIFIED_BUILD_DIR/boot" "$iso_dir/"
        cp -r "$UNIFIED_BUILD_DIR/isolinux" "$iso_dir/"
        
        # 변형 버전 데이터 복사
        cp -r "$UNIFIED_BUILD_DIR/work/variants" "$iso_dir/"
        cp "$UNIFIED_BUILD_DIR/work/unified-install.sh" "$iso_dir/"
        
        # ISO 생성 (부트 없이)
        cd "$UNIFIED_BUILD_DIR"
        xorriso -as mkisofs \
            -iso-level 3 \
            -full-iso9660-filenames \
            -volid "UNIFIEDARCH" \
            -appid "UnifiedArch OS Unified" \
            -publisher "UnifiedArch OS Project" \
            -preparer "UnifiedArch OS Build System" \
            -output "unifiedarch-unified-$VERSION.iso" \
            iso-content/
        
        log_success "수동 ISO 생성 완료"
    fi
    
    # 결과 파일 이동
    mkdir -p "$PROJECT_ROOT/iso"
    if [[ -f "$UNIFIED_BUILD_DIR/out"/*.iso ]]; then
        mv "$UNIFIED_BUILD_DIR/out"/*.iso "$PROJECT_ROOT/iso/"
        mv "$UNIFIED_BUILD_DIR/out"/*.sha256 "$PROJECT_ROOT/iso/" 2>/dev/null || true
    elif [[ -f "$UNIFIED_BUILD_DIR/unifiedarch-unified-$VERSION.iso" ]]; then
        mv "$UNIFIED_BUILD_DIR/unifiedarch-unified-$VERSION.iso" "$PROJECT_ROOT/iso/"
    fi
    
    cd "$PROJECT_ROOT"
}

# 체크섬 생성
create_checksums() {
    log_step "체크섬 생성 중..."
    
    cd "$PROJECT_ROOT/iso"
    if ls *.iso >/dev/null 2>&1; then
        sha256sum *.iso > sha256sums.txt
        md5sum *.iso > md5sums.txt
        log_success "체크섬 생성 완료"
    else
        log_warning "ISO 파일을 찾을 수 없음"
    fi
    
    cd "$PROJECT_ROOT"
}

# 빌드 결과 요약
show_build_summary() {
    log_step "빌드 결과 요약"
    
    echo ""
    echo -e "${CYAN}=== UnifiedArch OS 통합 ISO 빌드 완료 ===${NC}"
    echo ""
    echo -e "${GREEN}생성된 파일:${NC}"
    
    if [[ -d "$PROJECT_ROOT/iso" ]]; then
        ls -la "$PROJECT_ROOT/iso"/*.iso 2>/dev/null || echo "ISO 파일 없음"
        echo ""
        echo -e "${YELLOW}파일 크기:${NC}"
        du -h "$PROJECT_ROOT/iso"/*.iso 2>/dev/null || echo "크기 정보 없음"
    fi
    
    echo ""
    echo -e "${GREEN}포함된 변형 버전:${NC}"
    echo "  • Standard (2GB) - 모든 기능 포함"
    echo "  • Minimal (800MB) - 극단적 경량화"
    echo "  • Enterprise (3GB) - 서버 등급"
    echo "  • Gaming (4GB) - 게이밍 최적화"
    echo ""
    echo -e "${BLUE}총 크기: 약 10GB+${NC}"
    echo -e "${BLUE}빌드 ID: $BUILD_ID${NC}"
    echo ""
}

# 클린
clean_build() {
    log_step "통합 빌드 파일 정리 중..."
    
    if [[ -d "$UNIFIED_BUILD_DIR" ]]; then
        rm -rf "$UNIFIED_BUILD_DIR"
        log_success "통합 빌드 파일 정리 완료"
    else
        log_info "정리할 통합 빌드 파일 없음"
    fi
}

# 전체 빌드
full_unified_build() {
    banner
    log_info "UnifiedArch OS 통합 ISO 빌드 시작"
    log_info "빌드 ID: $BUILD_ID"
    
    check_build_environment
    create_variant_profiles
    create_boot_menu
    create_unified_profile
    integrate_variant_data
    create_unified_iso
    create_checksums
    show_build_summary
    
    log_success "통합 ISO 빌드 완료!"
}

# 도움말
show_help() {
    echo "UnifiedArch OS 통합 ISO 빌드 시스템"
    echo ""
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  all          - 전체 통합 빌드 (기본)"
    echo "  profiles     - 변형 버전 프로필만 생성"
    echo "  bootmenu     - 부트 메뉴만 생성"
    echo "  profile      - 통합 프로필만 생성"
    echo "  integrate    - 데이터 통합만 수행"
    echo "  iso          - ISO 이미지만 생성"
    echo "  checksum     - 체크섬만 생성"
    echo "  clean        - 빌드 파일 정리"
    echo "  help         - 이 도움말 표시"
    echo ""
    echo "환경 변수:"
    echo "  VERSION      - 버전 ($VERSION)"
    echo "  BUILD_DATE   - 빌드 날짜 ($BUILD_DATE)"
    echo "  BUILD_ID     - 빌드 ID ($BUILD_ID)"
}

# 메인 함수
main() {
    local action="${1:-all}"
    
    case "$action" in
        "all")
            full_unified_build
            ;;
        "profiles")
            check_build_environment
            create_variant_profiles
            ;;
        "bootmenu")
            create_boot_menu
            ;;
        "profile")
            create_unified_profile
            ;;
        "integrate")
            check_build_environment
            create_variant_profiles
            integrate_variant_data
            ;;
        "iso")
            check_build_environment
            create_variant_profiles
            create_boot_menu
            create_unified_profile
            integrate_variant_data
            create_unified_iso
            ;;
        "checksum")
            create_checksums
            ;;
        "clean")
            clean_build
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "알 수 없는 옵션: $action"
            show_help
            exit 1
            ;;
    esac
}

# 스크립트 실행
main "$@"
