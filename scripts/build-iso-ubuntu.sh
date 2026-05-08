#!/bin/bash
#
# UnifiedArch OS ISO 생성 스크립트 (Ubuntu/Debian 버전)
# Ubuntu 환경에서 부팅 가능한 ISO 생성
#
# 사용법: sudo ./build-iso-ubuntu.sh
#

set -euo pipefail

# ========== 설정 ==========
VERSION="${VERSION:-1.0.0}"
BUILD_DATE=$(date +%Y%m%d)
ISO_NAME="unifiedarch-${VERSION}-${BUILD_DATE}"

# 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build/iso"
CHROOT_DIR="${BUILD_DIR}/chroot"
ISO_DIR="${BUILD_DIR}/iso"
OUTPUT_DIR="${PROJECT_ROOT}/output"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ========== 로그 함수 ==========
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${PURPLE}[STEP]${NC} $1"; }

banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
  _   _   _   _   _   _   _   _   _  
 / \ / \ / \ / \ / \ / \ / \ / \ / \ 
( U | n | i | f | i | e | d | A | r )
 \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ 
                                     
   UnifiedArch OS ISO Builder v1.0
      Ubuntu/Debian Edition
EOF
    echo -e "${NC}"
}

# ========== 환경 확인 ==========
check_environment() {
    log_step "빌드 환경 확인 중..."
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 루트 권한으로 실행해야 합니다."
        log_info "사용법: sudo $0"
        exit 1
    fi
    
    # 필수 도구 확인
    local required_tools=("debootstrap" "squashfs-tools" "xorriso" "mtools" "grub-common" "isolinux")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "필수 도구가 설치되지 않았습니다: ${missing_tools[*]}"
        echo ""
        echo "설치 명령어:"
        echo "  sudo apt update"
        echo "  sudo apt install -y debootstrap squashfs-tools xorriso mtools grub-common isolinux syslinux-common"
        exit 1
    fi
    
    # 디스크 공간 확인 (최소 15GB)
    local available_space=$(df -BG "$PROJECT_ROOT" | tail -n1 | awk '{print $4}' | sed 's/G//')
    if [[ $available_space -lt 15 ]]; then
        log_warning "디스크 공간이 부족할 수 있습니다. (현재: ${available_space}GB, 권장: 15GB 이상)"
    fi
    
    # 디렉토리 생성
    mkdir -p "$BUILD_DIR" "$CHROOT_DIR" "$ISO_DIR" "$OUTPUT_DIR"
    
    log_success "빌드 환경 확인 완료"
}

# ========== 베이스 시스템 설치 ==========
install_base_system() {
    log_step "베이스 시스템 설치 중 (debootstrap)..."
    log_info "이 과정은 10-20분 정도 소요될 수 있습니다."
    
    # Ubuntu 22.04 (Jammy) 베이스 사용
    if [[ ! -d "$CHROOT_DIR/bin" ]]; then
        debootstrap --arch=amd64 jammy "$CHROOT_DIR" http://archive.ubuntu.com/ubuntu/
        log_success "베이스 시스템 설치 완료"
    else
        log_info "기존 chroot 디렉토리 발견, 건너뜀"
    fi
}

# ========== chroot 설정 ==========
configure_chroot() {
    log_step "chroot 시스템 설정 중..."
    
    # 필수 마운트
    mount --bind /dev "$CHROOT_DIR/dev"
    mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
    mount --bind /proc "$CHROOT_DIR/proc"
    mount --bind /sys "$CHROOT_DIR/sys"
    
    # sources.list 설정
    cat > "$CHROOT_DIR/etc/apt/sources.list" << 'EOF'
deb http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
EOF
    
    # hostname 설정
    echo "unifiedarch-live" > "$CHROOT_DIR/etc/hostname"
    
    # hosts 파일
    cat > "$CHROOT_DIR/etc/hosts" << 'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   unifiedarch-live
EOF
    
    # apt 설정
    chroot "$CHROOT_DIR" apt update
    
    log_success "chroot 기본 설정 완료"
}

# ========== 패키지 설치 ==========
install_packages() {
    log_step "패키지 설치 중..."
    
    # 필수 패키지
    local packages=(
        # 기본 시스템
        "linux-image-generic" "linux-headers-generic"
        "initramfs-tools" "systemd-sysv"
        
        # 네트워크
        "network-manager" "network-manager-gnome"
        "wireless-tools" "wpasupplicant"
        
        # 그래픽
        "xorg" "xserver-xorg" "xinit"
        "mesa-utils" "x11-xserver-utils"
        
        # 데스크톱 (경량)
        "xfce4" "xfce4-goodies" "lightdm"
        
        # 기본 앱
        "firefox" "thunderbird"
        "libreoffice-writer" "libreoffice-calc"
        "vlc" "gimp"
        "xfce4-terminal" "thunar"
        
        # 시스템 도구
        "gparted" "gnome-disk-utility"
        "htop" "tmux" "vim" "nano"
        
        # 폰트
        "fonts-noto" "fonts-noto-cjk"
        
        # 기타
        "sudo" "openssh-client" "curl" "wget" "git"
    )
    
    log_info "패키지 설치 중... (시간이 다소 걸릴 수 있습니다)"
    DEBIAN_FRONTEND=noninteractive chroot "$CHROOT_DIR" apt install -y "${packages[@]}"
    
    log_success "패키지 설치 완료"
}

# ========== 사용자 설정 ==========
configure_users() {
    log_step "사용자 계정 설정 중..."
    
    # 기본 사용자 생성
    chroot "$CHROOT_DIR" useradd -m -s /bin/bash -G sudo,audio,video,plugdev unifiedarch
    echo "unifiedarch:unifiedarch" | chroot "$CHROOT_DIR" chpasswd
    
    # root 비밀번호
    echo "root:unifiedarch" | chroot "$CHROOT_DIR" chpasswd
    
    # sudo 설정
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" > "$CHROOT_DIR/etc/sudoers.d/10-nopasswd"
    chmod 440 "$CHROOT_DIR/etc/sudoers.d/10-nopasswd"
    
    # 자동 로그인 설정
    mkdir -p "$CHROOT_DIR/etc/lightdm/lightdm.conf.d"
    cat > "$CHROOT_DIR/etc/lightdm/lightdm.conf.d/10-autologin.conf" << 'EOF'
[Seat:*]
autologin-user=unifiedarch
autologin-user-timeout=0
EOF
    
    log_success "사용자 설정 완료"
}

# ========== 시스템 커스터마이제이션 ==========
customize_system() {
    log_step "시스템 커스터마이제이션 중..."
    
    # 로케일 설정
    chroot "$CHROOT_DIR" locale-gen en_US.UTF-8 ko_KR.UTF-8
    echo "LANG=ko_KR.UTF-8" > "$CHROOT_DIR/etc/default/locale"
    
    # 시간대 설정
    chroot "$CHROOT_DIR" ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
    
    # 서비스 활성화
    chroot "$CHROOT_DIR" systemctl enable NetworkManager
    chroot "$CHROOT_DIR" systemctl enable lightdm
    
    # OS 릴리즈 정보
    cat > "$CHROOT_DIR/etc/os-release" << 'EOF'
NAME="UnifiedArch OS"
VERSION="1.0.0 (Aurora)"
ID=unifiedarch
ID_LIKE=ubuntu
PRETTY_NAME="UnifiedArch OS 1.0.0 (Aurora)"
ANSI_COLOR="0;34"
HOME_URL="https://unifiedarch.org"
EOF
    
    # 시작 스크립트
    cat > "$CHROOT_DIR/usr/local/bin/unifiedarch-welcome" << 'EOF'
#!/bin/bash
echo "========================================="
echo "  Welcome to UnifiedArch OS!"
echo "========================================="
echo ""
echo "시스템 정보:"
echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo "  커널: $(uname -r)"
echo "  메모리: $(free -h | grep Mem | awk '{print $2}')"
echo ""
echo "설치를 시작하려면:"
echo "  unifiedarch-install"
echo ""
EOF
    chmod +x "$CHROOT_DIR/usr/local/bin/unifiedarch-welcome"
    
    # 자동 시작 설정
    mkdir -p "$CHROOT_DIR/home/unifiedarch/.config/autostart"
    cat > "$CHROOT_DIR/home/unifiedarch/.config/autostart/welcome.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=UnifiedArch Welcome
Exec=xfce4-terminal -e /usr/local/bin/unifiedarch-welcome
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    chroot "$CHROOT_DIR" chown -R unifiedarch:unifiedarch /home/unifiedarch
    
    log_success "시스템 커스터마이제이션 완료"
}

# ========== 커널 및 initramfs ==========
prepare_kernel() {
    log_step "커널 및 initramfs 준비 중..."
    
    # initramfs 생성
    chroot "$CHROOT_DIR" update-initramfs -u -k all
    
    # 커널 복사
    mkdir -p "$ISO_DIR/boot"
    cp "$CHROOT_DIR/boot/vmlinuz-"* "$ISO_DIR/boot/vmlinuz"
    cp "$CHROOT_DIR/boot/initrd.img-"* "$ISO_DIR/boot/initrd.img"
    
    log_success "커널 준비 완료"
}

# ========== squashfs 생성 ==========
create_squashfs() {
    log_step "squashfs 파일시스템 생성 중..."
    
    mkdir -p "$ISO_DIR/casper"
    
    # squashfs 생성
    mksquashfs "$CHROOT_DIR" "$ISO_DIR/casper/filesystem.squashfs" \
        -comp xz -noappend -no-recovery
    
    log_success "squashfs 생성 완료"
}

# ========== 부트로더 설정 ==========
setup_bootloader() {
    log_step "부트로더 설정 중..."
    
    # isolinux 설정
    mkdir -p "$ISO_DIR/isolinux"
    cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_DIR/isolinux/"
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$ISO_DIR/isolinux/"
    cp /usr/lib/syslinux/modules/bios/libcom32.c32 "$ISO_DIR/isolinux/"
    cp /usr/lib/syslinux/modules/bios/libutil.c32 "$ISO_DIR/isolinux/"
    cp /usr/lib/syslinux/modules/bios/vesamenu.c32 "$ISO_DIR/isolinux/"
    
    # isolinux.cfg
    cat > "$ISO_DIR/isolinux/isolinux.cfg" << 'EOF'
UI vesamenu.c32
MENU TITLE UnifiedArch OS Live System
MENU BACKGROUND /isolinux/splash.png
MENU WIDTH 72
MENU MARGIN 10
MENU ROWS 6
MENU TABMSG Press TAB to edit options

LABEL live
    MENU LABEL ^UnifiedArch OS Live
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.img boot=casper quiet splash --
    
LABEL safe
    MENU LABEL ^Safe Graphics Mode
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.img boot=casper nomodeset quiet --
    
LABEL memtest
    MENU LABEL ^Memory Test
    LINUX16 /boot/memtest86+.bin

LABEL hd
    MENU LABEL ^Boot from Hard Disk
    LOCALBOOT 0x80
EOF
    
    # GRUB 설정 (UEFI)
    mkdir -p "$ISO_DIR/boot/grub"
    cat > "$ISO_DIR/boot/grub/grub.cfg" << 'EOF'
set default="0"
set timeout=10

menuentry "UnifiedArch OS Live" {
    linux /boot/vmlinuz boot=casper quiet splash --
    initrd /boot/initrd.img
}

menuentry "Safe Graphics Mode" {
    linux /boot/vmlinuz boot=casper nomodeset quiet --
    initrd /boot/initrd.img
}

menuentry "Boot from Hard Disk" {
    exit
}
EOF
    
    log_success "부트로더 설정 완료"
}

# ========== ISO 생성 ==========
create_iso() {
    log_step "ISO 이미지 생성 중..."
    
    local iso_path="${OUTPUT_DIR}/${ISO_NAME}.iso"
    
    # xorriso로 ISO 생성
    xorriso -as mkisofs \
        -iso-level 3 \
        -o "$iso_path" \
        -full-iso9660-filenames \
        -volid "UnifiedArch" \
        -appid "UnifiedArch OS" \
        -publisher "UnifiedArch OS Project" \
        -preparer "UnifiedArch Build System" \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --grub2-boot-info \
        -eltorito-alt-boot \
        -e boot/grub/grub.cfg \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        "$ISO_DIR"
    
    if [[ -f "$iso_path" ]]; then
        local iso_size=$(du -h "$iso_path" | cut -f1)
        
        # 체크섬 생성
        cd "$OUTPUT_DIR"
        sha256sum "${ISO_NAME}.iso" > "${ISO_NAME}.iso.sha256"
        md5sum "${ISO_NAME}.iso" > "${ISO_NAME}.iso.md5"
        
        log_success "ISO 생성 완료!"
        echo ""
        echo -e "${GREEN}=========================================${NC}"
        echo -e "${GREEN}  UnifiedArch OS ISO Build Complete!${NC}"
        echo -e "${GREEN}=========================================${NC}"
        echo ""
        echo -e "  ${BOLD}ISO 파일:${NC} $iso_path"
        echo -e "  ${BOLD}크기:${NC} $iso_size"
        echo ""
        echo -e "  ${BOLD}USB 굽기:${NC}"
        echo "  sudo dd if=$iso_path of=/dev/sdX bs=4M status=progress && sync"
        echo ""
        echo -e "  ${BOLD}QEMU 테스트:${NC}"
        echo "  qemu-system-x86_64 -m 4G -cdrom $iso_path"
        echo ""
    else
        log_error "ISO 생성 실패"
        return 1
    fi
}

# ========== 정리 ==========
cleanup() {
    log_step "정리 중..."
    
    # chroot 마운트 해제
    umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    umount "$CHROOT_DIR/dev" 2>/dev/null || true
    umount "$CHROOT_DIR/proc" 2>/dev/null || true
    umount "$CHROOT_DIR/sys" 2>/dev/null || true
    
    # 전체 정리
    if [[ "${CLEANUP:-false}" == "true" ]]; then
        rm -rf "$BUILD_DIR"
        log_info "빌드 디렉토리 정리 완료"
    fi
}

# ========== 도움말 ==========
show_help() {
    echo "UnifiedArch OS ISO 빌드 스크립트 (Ubuntu/Debian)"
    echo ""
    echo "사용법: sudo $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  build    - ISO 빌드 (기본)"
    echo "  clean    - 빌드 파일 정리"
    echo "  help     - 이 도움말"
    echo ""
    echo "환경 변수:"
    echo "  VERSION  - 버전 (기본: 1.0.0)"
    echo "  CLEANUP  - 빌드 후 정리 (true/false)"
    echo ""
    echo "요구사항:"
    echo "  - Ubuntu/Debian 시스템"
    echo "  - 루트 권한"
    echo "  - 최소 15GB 디스크 공간"
}

# ========== 메인 ==========
main() {
    local action="${1:-build}"
    
    case "$action" in
        build)
            banner
            check_environment
            install_base_system
            configure_chroot
            install_packages
            configure_users
            customize_system
            prepare_kernel
            create_squashfs
            setup_bootloader
            create_iso
            cleanup
            ;;
        clean)
            cleanup
            rm -rf "$BUILD_DIR"
            log_success "정리 완료"
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
