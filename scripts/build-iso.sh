#!/bin/bash
# UnifiedArch OS ISO 생성 스크립트
# 실제로 동작하는 archiso 기반 ISO 빌드 시스템

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
BUILD_DATE=$(date +%Y%m%d)
ISO_NAME="unifiedarch-$VERSION-$BUILD_DATE"

# 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
ISO_WORK_DIR="$BUILD_DIR/iso/work"
ISO_OUT_DIR="$BUILD_DIR/iso/out"
PROFILE_DIR="$BUILD_DIR/iso/profile"

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
                                              
         실제 ISO 생성 시스템 v1.0
EOF
    echo -e "${NC}"
}

# 환경 확인
check_iso_environment() {
    log_step "ISO 생성 환경 확인 중..."
    
    # archiso 설치 확인
    if ! command -v mkarchiso >/dev/null 2>&1; then
        log_error "archiso가 설치되지 않았습니다. 'pacman -S archiso'로 설치하세요."
        exit 1
    fi
    
    # 필수 도구 확인
    local required_tools=("pacman" "git" "tar" "gzip" "squashfs-tools" "libisoburn")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "필수 도구를 찾을 수 없음: $tool"
            exit 1
        fi
    done
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "ISO 생성은 루트 권한으로 실행해야 합니다."
        exit 1
    fi
    
    # 작업 디렉토리 생성
    mkdir -p "$ISO_WORK_DIR" "$ISO_OUT_DIR" "$PROFILE_DIR"
    
    log_success "ISO 생성 환경 확인 완료"
}

# archiso 프로필 생성
create_archiso_profile() {
    log_step "archiso 프로필 생성 중..."
    
    # 프로필 설정 파일
    cat > "$PROFILE_DIR/profiledef.sh" << EOF
#!/usr/bin/env bash
#
# UnifiedArch OS archiso profile

iso_name="unifiedarch"
iso_label="UNIFIEDARCH"
iso_publisher="UnifiedArch OS Project"
iso_application="UnifiedArch OS Live/Install"
iso_version="$VERSION"
install_dir="unifiedarch"
work_dir="$ISO_WORK_DIR"
out_dir="$ISO_OUT_DIR"
bootmodes=("bios" "uefi")
arch="x86_64"
pacman_conf="pacman.conf"
EOF

    chmod +x "$PROFILE_DIR/profiledef.sh"
    
    # pacman 설정
    cat > "$PROFILE_DIR/pacman.conf" << 'EOF'
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

    log_success "archiso 프로필 생성 완료"
}

# 패키지 목록 생성
create_package_lists() {
    log_step "패키지 목록 생성 중..."
    
    # 기본 시스템 패키지
    cat > "$PROFILE_DIR/packages.x86_64" << 'EOF'
# Base system
base
base-devel
linux
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
mc
htop
tree

# Network tools
networkmanager
network-manager-applet
wireless_tools
wpa_supplicant
bluez
bluez-utils
usbutils
pciutils
usb_modeswitch

# Display drivers
mesa
xf86-video-amdgpu
xf86-video-intel
xf86-video-nouveau
xf86-video-vesa
vulkan-radeon
vulkan-intel
libva-mesa-driver
mesa-vdpau

# Desktop environment (GNOME)
gnome
gnome-extra
gdm
gnome-tweaks
nautilus
gnome-terminal
gnome-control-center

# Basic applications
firefox
libreoffice-fresh
libreoffice-still
evince
gnome-calculator
gnome-calendar
gnome-weather
gnome-maps
gnome-contacts
gnome-clocks
gnome-photos
gnome-music
gnome-videos

# Multimedia
vlc
rhythmbox
cheese
totem
shotwell
gimp
inkscape

# Development tools
git
vim
code
make
gcc
python
python-pip
nodejs
npm

# System tools
gparted
baobab
disk-utility
gnome-disks
seahorse
dconf-editor

# Fonts
noto-fonts
noto-fonts-cjk
noto-fonts-emoji
ttf-liberation
ttf-dejavu

# Terminal utilities
bash-completion
zsh
zsh-completions
fish
tmux
screen

# Archive tools
unzip
unrar
p7zip
zip
tar
gzip
bzip2
xz

# Additional utilities
tree
jq
rsync
lsof
strace
ltrace
gdb

# UnifiedArch specific packages (will be added during build)
EOF

    # 라이브 시스템 패키지
    cat > "$PROFILE_DIR/packages.x86_64" << 'EOF'
# Live system packages
calamares
squashfs-tools
EOF

    log_success "패키지 목록 생성 완료"
}

# 시스템 설정 파일 생성
create_system_configs() {
    log_step "시스템 설정 파일 생성 중..."
    
    # 그룹 생성 스크립트
    cat > "$PROFILE_DIR/airootfs/root/customize_airootfs.sh" << 'EOF'
#!/usr/bin/env bash
set -e -u

# 사용자 정의 스크립트
echo "UnifiedArch OS 라이브 시스템 설정 중..."

# 기본 사용자 설정
useradd -m -G wheel,video,audio,storage -s /bin/bash unifiedarch
echo "unifiedarch:unifiedarch" | chpasswd

# sudoers 설정
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

# 네트워크 설정
systemctl enable NetworkManager
systemctl enable bluetooth

# GDM 활성화 (GUI 로그인)
systemctl enable gdm

# 기본 언어 설정
echo "LANG=ko_KR.UTF-8" > /etc/locale.conf
echo "FONT=ter-132n" >> /etc/vconsole.conf

# 시간대 설정
ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

# 호스트 이름
echo "unifiedarch-live" > /etc/hostname

# hosts 파일
cat > /etc/hosts << 'HOSTSEOF'
127.0.0.1 localhost
::1 localhost
127.0.1.1 unifiedarch-live.localdomain unifiedarch-live
HOSTSEOF

# 데스크톱 설정
# GNOME 기본 설정
gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/gnome/adwaita-day.jpg'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'

# 자동 로그인 비활성화 (보안)
gsettings set org.gnome.desktop.session auto-save-session false

# 파워 관리 설정
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0

# 프라이버시 설정
gsettings set org.gnome.desktop.privacy report-technical-problems false
gsettings set org.gnome.desktop.privacy send-software-usage-stats false

# 설치 프로그램 바로가기 생성
mkdir -p /home/unifiedarch/Desktop
cat > /home/unifiedarch/Desktop/install-unifiedarch.desktop << 'DESKTOPEOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install UnifiedArch OS
Comment=Install UnifiedArch OS to your computer
Exec=calamares
Icon=system-software-install
Terminal=false
Categories=System;Settings;
DESKTOPEOF

chmod +x /home/unifiedarch/Desktop/install-unifiedarch.desktop
chown unifiedarch:unifiedarch /home/unifiedarch/Desktop/install-unifiedarch.desktop

# 설치 스크립트 복사
mkdir -p /opt/unifiedarch
cp -r /run/archiso/copytoram/usr/lib/unifiedarch/* /opt/unifiedarch/ 2>/dev/null || true

# 시작 스크립트 생성
cat > /usr/local/bin/unifiedarch-setup << 'SETUPEOF'
#!/bin/bash
# UnifiedArch OS 초기 설정 스크립트

echo "UnifiedArch OS 초기 설정 시작..."

# 하드웨어 감지
echo "하드웨어 감지 중..."
lspci | grep -i vga
lspci | grep -i audio
lsusb | head -5

# 네트워크 설정
echo "네트워크 설정 중..."
nmcli dev status
nmcli connection show

# 설치 프로그램 정보
echo ""
echo "UnifiedArch OS 설치:"
echo "1. 바탕화면의 'Install UnifiedArch OS' 아이콘 클릭"
echo "2. 또는 터미널에서 'calamares' 실행"
echo "3. 설치 마법사 안내에 따라 설치 진행"
echo ""
echo "도움이 필요하면:"
echo "- 터미널에서 'unifiedarch-help' 실행"
echo "- 온라인 문서: https://docs.unifiedarch.org"
echo ""
SETUPEOF

chmod +x /usr/local/bin/unifiedarch-setup

# 도움말 스크립트 생성
cat > /usr/local/bin/unifiedarch-help << 'HELPEOF'
#!/bin/bash
# UnifiedArch OS 도움말 스크립트

echo "UnifiedArch OS 도움말"
echo "=================="
echo ""
echo "빠른 시작:"
echo "1. 설치: 바탕화면의 설치 아이콘 클릭"
echo "2. 네트워크: 상단 패널의 네트워크 아이콘"
echo "3. 터미널: Ctrl+Alt+T 또는 앱 메뉴에서 터미널"
echo ""
echo "주요 명령어:"
echo "- unifiedarch-setup: 초기 설정"
echo "- unifiedarch-info: 시스템 정보"
echo "- calamares: 설치 프로그램"
echo "- nmcli: 네트워크 관리"
echo ""
echo "파일 시스템:"
echo "- /home/unifiedarch: 사용자 홈"
echo "- /opt/unifiedarch: UnifiedArch 도구"
echo "- /usr/share/backgrounds: 배경화면"
echo ""
echo "문서:"
echo "- 온라인: https://docs.unifiedarch.org"
echo "- 로컬: /usr/share/doc/unifiedarch/"
echo ""
HELPEOF

chmod +x /usr/local/bin/unifiedarch-help

# 정보 스크립트 생성
cat > /usr/local/bin/unifiedarch-info << 'INFOEOF'
#!/bin/bash
# UnifiedArch OS 정보 스크립트

echo "UnifiedArch OS 정보"
echo "==================="
echo "버전: 1.0.0"
echo "아키텍처: $(uname -m)"
echo "커널: $(uname -r)"
echo ""
echo "하드웨어 정보:"
echo "CPU: $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)"
echo "메모리: $(free -h | grep '^Mem:' | awk '{print $2}')"
echo "디스크: $(df -h / | tail -n1 | awk '{print $2}')"
echo ""
echo "네트워크:"
ip addr show | grep -E '^[0-9]+:' | awk '{print $2}' | cut -d: -f1
echo ""
echo "그래픽:"
lspci | grep -i vga | head -n1
echo ""
echo "사용 가능한 공간:"
df -h / | tail -n1 | awk '{print $4}'
echo ""
INFOEOF

chmod +x /usr/local/bin/unifiedarch-info

# 시작 애플리케이션 설정
mkdir -p /home/unifiedarch/.config/autostart
cat > /home/unifiedarch/.config/autostart/unifiedarch-welcome.desktop << 'AUTOEOF'
[Desktop Entry]
Type=Application
Name=UnifiedArch Welcome
Exec=gnome-terminal -- /usr/local/bin/unifiedarch-setup
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
AUTOEOF

chown -R unifiedarch:unifiedarch /home/unifiedarch

# 설치 프로그램 설정 (Calamares)
if command -v calamares >/dev/null 2>&1; then
    # Calamares 설정
    mkdir -p /etc/calamares
    cat > /etc/calamares/settings.conf << 'CALAMARESEOF'
modules-search: [ local ]
instances:
- id: before
  module: shellprocess
  config: shellprocess_before.conf
- id: partition
  module: partition
  config: partition.conf
- id: mount
  module: mount
  config: mount.conf
- id: unpackfs
  module: unpackfs
  config: unpackfs.conf
- id: machineid
  module: machineid
  config: machineid.conf
- id: fstab
  module: fstab
  config: fstab.conf
- id: locale
  module: locale
  config: locale.conf
- id: keyboard
  module: keyboard
  config: keyboard.conf
- id: localecfg
  module: localecfg
  config: localecfg.conf
- id: users
  module: users
  config: users.conf
- id: displaymanager
  module: displaymanager
  config: displaymanager.conf
- id: packages
  module: packages
  config: packages.conf
- id: luksbootkeyfilesetup
  module: luksbootkeyfilesetup
  config: luksbootkeyfilesetup.conf
- id: luksgeneratenotify
  module: luksgeneratenotify
  config: luksgeneratenotify.conf
- id: luksopensetup
  module: luksopensetup
  config: luksopensetup.conf
- id: removeuser
  module: removeuser
  config: removeuser.conf
- id: shellprocess@after
  module: shellprocess
  config: shellprocess_after.conf
sequence:
- show:
  - before
  - partition
  - mount
  - unpackfs
  - machineid
  - fstab
  - locale
  - keyboard
  - localecfg
  - users
  - displaymanager
  - packages
  - luksbootkeyfilesetup
  - luksgeneratenotify
  - luksopensetup
  - removeuser
  - shellprocess@after
branding: unifiedarch
prompt-install: false
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: false
hide-back-and-next-during-exec: false
quit-at-end: false
CALAMARESEOF
fi

echo "UnifiedArch OS 라이브 시스템 설정 완료"
EOF

    chmod +x "$PROFILE_DIR/airootfs/root/customize_airootfs.sh"
    
    log_success "시스템 설정 파일 생성 완료"
}

# Calamares 설정 파일 생성
create_calamares_config() {
    log_step "Calamares 설정 파일 생성 중..."
    
    mkdir -p "$PROFILE_DIR/airootfs/etc/calamares/modules"
    
    # Calamares 기본 설정
    cat > "$PROFILE_DIR/airootfs/etc/calamares/modules/unifiedarch.conf" << 'CALAMARESEOF'
# UnifiedArch OS Calamares 설정

displaymanager: gdm
hostname: unifiedarch
username: user
password: ""
sudoersGroup: wheel
setRootPassword: true
doAutoLogin: false
CALAMARESEOF
    
    log_success "Calamares 설정 파일 생성 완료"
}

# 부트로더 설정
create_bootloader_config() {
    log_step "부트로더 설정 생성 중..."
    
    # GRUB 설정
    mkdir -p "$PROFILE_DIR/efiboot/loader/entries"
    
    cat > "$PROFILE_DIR/efiboot/loader/loader.conf" << 'GRUBEOF'
default unifiedarch
timeout 3
console-mode max
GRUBEOF
    
    cat > "$PROFILE_DIR/efiboot/loader/entries/unifiedarch.conf" << 'GRUBENTRIEEOF'
title   UnifiedArch OS Live
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options  boot=live liveimg=1 quiet splash
GRUBENTRIEEOF
    
    log_success "부트로더 설정 생성 완료"
}

# ISO 빌드 실행
build_iso() {
    log_step "ISO 빌드 실행 중..."
    
    cd "$PROFILE_DIR"
    
    # 빌드 시작
    log_info "archiso로 ISO 빌드 시작..."
    if mkarchiso -v -w "$ISO_WORK_DIR" -o "$ISO_OUT_DIR" config/; then
        log_success "ISO 빌드 완료"
        
        # 결과 파일 확인
        local iso_file=$(find "$ISO_OUT_DIR" -name "*.iso" | head -n1)
        if [[ -f "$iso_file" ]]; then
            local iso_size=$(du -h "$iso_file" | cut -f1)
            log_success "ISO 파일 생성됨: $(basename "$iso_file") ($iso_size)"
            
            # 체크섬 생성
            cd "$ISO_OUT_DIR"
            sha256sum "$(basename "$iso_file")" > "$(basename "$iso_file").sha256"
            md5sum "$(basename "$iso_file")" > "$(basename "$iso_file").md5"
            
            log_success "체크섬 파일 생성됨"
            
            # 최종 결과 디렉토리로 복사
            mkdir -p "$BUILD_DIR/final"
            cp "$iso_file" "$BUILD_DIR/final/$ISO_NAME.iso"
            cp "$(basename "$iso_file").sha256" "$BUILD_DIR/final/$ISO_NAME.iso.sha256"
            cp "$(basename "$iso_file").md5" "$BUILD_DIR/final/$ISO_NAME.iso.md5"
            
            log_success "최종 ISO 생성됨: $BUILD_DIR/final/$ISO_NAME.iso"
            
            return 0
        else
            log_error "ISO 파일을 찾을 수 없음"
            return 1
        fi
    else
        log_error "ISO 빌드 실패"
        return 1
    fi
}

# 빌드 후 정리
cleanup_build() {
    log_step "빌드 후 정리 중..."
    
    # 임시 파일 정리 (선택적)
    if [[ "${1:-}" == "full" ]]; then
        if [[ -d "$ISO_WORK_DIR" ]]; then
            rm -rf "$ISO_WORK_DIR"
            log_info "작업 디렉토리 정리 완료"
        fi
    fi
    
    log_success "정리 완료"
}

# ISO 테스트
test_iso() {
    log_step "ISO 테스트 중..."
    
    local iso_file="$BUILD_DIR/final/$ISO_NAME.iso"
    
    if [[ -f "$iso_file" ]]; then
        # ISO 정보 확인
        log_info "ISO 정보:"
        file "$iso_file"
        
        # ISO 크기 확인
        local iso_size=$(stat -c%s "$iso_file")
        log_info "ISO 크기: $((iso_size / 1024 / 1024)) MB"
        
        # ISO 마운트 테스트 (선택적)
        if command -v mount >/dev/null 2>&1; then
            local mount_point="/tmp/unifiedarch-iso-test"
            mkdir -p "$mount_point"
            
            if mount -o loop,ro "$iso_file" "$mount_point" 2>/dev/null; then
                log_success "ISO 마운트 테스트 통과"
                
                # 부트 파일 확인
                if [[ -f "$mount_point/boot/vmlinuz-linux" ]]; then
                    log_success "커널 파일 존재"
                else
                    log_warning "커널 파일 없음"
                fi
                
                if [[ -f "$mount_point/boot/initramfs-linux.img" ]]; then
                    log_success "initramfs 파일 존재"
                else
                    log_warning "initramfs 파일 없음"
                fi
                
                umount "$mount_point"
            else
                log_warning "ISO 마운트 실패"
            fi
            
            rmdir "$mount_point"
        fi
        
        log_success "ISO 테스트 완료"
    else
        log_error "ISO 파일 없음: $iso_file"
        return 1
    fi
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS ISO 생성 스크립트"
    echo ""
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  build        - ISO 빌드 (기본)"
    echo "  clean        - 빌드 파일 정리"
    echo "  clean-full   - 완전 정리"
    echo "  test         - ISO 테스트"
    echo "  help         - 이 도움말 표시"
    echo ""
    echo "환경 변수:"
    echo "  VERSION      - 버전 ($VERSION)"
    echo "  BUILD_DATE   - 빌드 날짜 ($BUILD_DATE)"
    echo "  ISO_NAME     - ISO 이름 ($ISO_NAME)"
}

# 메인 함수
main() {
    local action="${1:-build}"
    
    banner
    
    case "$action" in
        "build")
            check_iso_environment
            create_archiso_profile
            create_package_lists
            create_system_configs
            create_calamares_config
            create_bootloader_config
            if build_iso; then
                test_iso
                cleanup_build
            fi
            ;;
        "clean")
            cleanup_build
            ;;
        "clean-full")
            cleanup_build "full"
            ;;
        "test")
            test_iso
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
