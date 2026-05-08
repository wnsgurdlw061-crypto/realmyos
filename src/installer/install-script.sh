#!/bin/bash
# UnifiedArch OS 자동 설치 스크립트
# Arch Linux 기반 통합 설치 시스템

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 설정 파일 경로
CONFIG_FILE="/etc/unifiedarch/config.yaml"
PACKAGE_PROFILE="/etc/unifiedarch/package-profiles.yaml"

# 기본 설정
DEFAULT_LANG="ko_KR.UTF-8"
DEFAULT_TIMEZONE="Asia/Seoul"
DEFAULT_HOSTNAME="unifiedarch"

# 설치 단계별 함수
check_requirements() {
    log_info "설치 요구사항 확인 중..."
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 루트 권한으로 실행해야 합니다."
        exit 1
    fi
    
    # 인터넷 연결 확인
    if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
        log_error "인터넷 연결이 필요합니다."
        exit 1
    fi
    
    # UEFI 모드 확인
    if [[ -d /sys/firmware/efi ]]; then
        UEFI_MODE=true
        log_info "UEFI 모드 감지됨"
    else
        UEFI_MODE=false
        log_warning "BIOS 모드 감지됨"
    fi
    
    log_success "요구사항 확인 완료"
}

detect_hardware() {
    log_info "하드웨어 자동 감지 중..."
    
    # GPU 감지
    if lspci | grep -i nvidia >/dev/null; then
        GPU_TYPE="nvidia"
        log_info "NVIDIA GPU 감지됨"
    elif lspci | grep -i amd >/dev/null; then
        GPU_TYPE="amd"
        log_info "AMD GPU 감지됨"
    elif lspci | grep -i intel >/dev/null; then
        GPU_TYPE="intel"
        log_info "Intel GPU 감지됨"
    else
        GPU_TYPE="unknown"
        log_warning "GPU를 감지할 수 없음"
    fi
    
    # 무선 카드 감지
    if lspci | grep -i "wireless\|wifi" >/dev/null || lsusb | grep -i "wireless\|wifi" >/dev/null; then
        WIFI_AVAILABLE=true
        log_info "무선 네트워크 카드 감지됨"
    else
        WIFI_AVAILABLE=false
    fi
    
    # 배터리 감지 (노트북)
    if [[ -d /sys/class/power_supply/BAT0 ]]; then
        IS_LAPTOP=true
        log_info "노트북으로 감지됨 (배터리 있음)"
    else
        IS_LAPTOP=false
    fi
    
    log_success "하드웨어 감지 완료"
}

partition_disk() {
    log_info "디스크 파티셔닝 중..."
    
    # 디스크 선택 (자동 또는 수동)
    if [[ "${AUTO_PARTITION:-true}" == "true" ]]; then
        # 자동 파티셔닝
        DISK=$(lsblk -d -o NAME | grep -v loop | head -n 1)
        log_info "자동 파티셔닝: /dev/$DISK 사용"
        
        if [[ "$UEFI_MODE" == true ]]; then
            # UEFI 파티셔닝
            sfdisk "/dev/$DISK" << EOF
label: gpt
size=512M, type=EF00
size=2G, type=8200
type=8300
EOF
            
            mkfs.fat -F32 "/dev/${DISK}1"
            mkswap "/dev/${DISK}2"
            mkfs.ext4 "/dev/${DISK}3"
            
            ESP_PARTITION="/dev/${DISK}1"
            SWAP_PARTITION="/dev/${DISK}2"
            ROOT_PARTITION="/dev/${DISK}3"
        else
            # BIOS 파티셔닝
            sfdisk "/dev/$DISK" << EOF
label: dos
size=2G, type=82
type=83
EOF
            
            mkswap "/dev/${DISK}1"
            mkfs.ext4 "/dev/${DISK}2"
            
            SWAP_PARTITION="/dev/${DISK}1"
            ROOT_PARTITION="/dev/${DISK}2"
        fi
    else
        # 수동 파티셔닝
        log_warning "수동 파티셔닝은 아직 구현되지 않았습니다."
        exit 1
    fi
    
    log_success "파티셔닝 완료"
}

mount_filesystems() {
    log_info "파일 시스템 마운트 중..."
    
    # 루트 파티션 마운트
    mount "$ROOT_PARTITION" /mnt
    
    # 부트 파티션 마운트 (UEFI)
    if [[ "$UEFI_MODE" == true ]]; then
        mkdir -p /mnt/boot
        mount "$ESP_PARTITION" /mnt/boot
    fi
    
    # 스왑 활성화
    swapon "$SWAP_PARTITION"
    
    log_success "파일 시스템 마운트 완료"
}

install_base_system() {
    log_info "기본 시스템 설치 중..."
    
    # 기본 패키지 설치
    pacstrap /mnt \
        base \
        base-devel \
        linux \
        linux-firmware \
        networkmanager \
        bluez \
        cups \
        pulseaudio \
        alsa-utils \
        vim \
        git
    
    log_success "기본 시스템 설치 완료"
}

generate_fstab() {
    log_info "fstab 생성 중..."
    genfstab -U /mnt >> /mnt/etc/fstab
    log_success "fstab 생성 완료"
}

chroot_setup() {
    log_info "chroot 환경 설정 중..."
    
    # chroot로 설정 스크립트 복사
    cp "$0" /mnt/root/unifiedarch-installer
    chmod +x /mnt/root/unifiedarch-installer
    
    # chroot 실행
    arch-chroot /mnt /root/unifiedarch-installer chroot_phase
}

# chroot 단계 설정
chroot_phase() {
    log_info "chroot 환경 설정 시작"
    
    # 시간대 설정
    ln -sf /usr/share/zoneinfo/"$DEFAULT_TIMEZONE" /etc/localtime
    hwclock --systohc
    
    # 로케일 설정
    sed -i 's/#ko_KR.UTF-8/ko_KR.UTF-8/' /etc/locale.gen
    locale-gen
    echo "LANG=$DEFAULT_LANG" > /etc/locale.conf
    
    # 호스트네임 설정
    echo "$DEFAULT_HOSTNAME" > /etc/hostname
    
    # hosts 파일 설정
    cat > /etc/hosts << EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 $DEFAULT_HOSTNAME.localdomain $DEFAULT_HOSTNAME
EOF
    
    # Initramfs 생성
    mkinitcpio -P
    
    # 루트 비밀번호 설정
    log_warning "루트 비밀번호를 설정해주세요:"
    passwd
    
    # 사용자 생성
    log_info "기본 사용자 생성 중..."
    useradd -m -G wheel,audio,video,storage -s /bin/bash unifiedarch
    log_warning "unifiedarch 사용자 비밀번호를 설정해주세요:"
    passwd unifiedarch
    
    # sudo 설정
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    
    # 네트워크 서비스 활성화
    systemctl enable NetworkManager
    
    # Bluetooth 활성화 (노트북인 경우)
    if [[ "$IS_LAPTOP" == true ]]; then
        systemctl enable bluetooth
    fi
    
    # 프린터 서비스 활성화
    systemctl enable cups
    
    log_success "chroot 설정 완료"
}

install_desktop_environment() {
    local desktop=${1:-"gnome"}
    
    log_info "데스크톱 환경 설치 중: $desktop"
    
    case "$desktop" in
        "gnome")
            pacman -S --noconfirm gnome gnome-extra gdm
            systemctl enable gdm
            ;;
        "kde")
            pacman -S --noconfirm plasma plasma-meta sddm
            systemctl enable sddm
            ;;
        "xfce")
            pacman -S --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
            systemctl enable lightdm
            ;;
        "i3")
            pacman -S --noconfirm i3-wm i3lock i3status dmenu rxvt-unicode
            ;;
        *)
            log_error "지원되지 않는 데스크톱 환경: $desktop"
            return 1
            ;;
    esac
    
    log_success "데스크톱 환경 설치 완료"
}

install_gpu_drivers() {
    log_info "GPU 드라이버 설치 중..."
    
    case "$GPU_TYPE" in
        "nvidia")
            pacman -S --noconfirm nvidia-dkms nvidia-settings
            ;;
        "amd")
            pacman -S --noconfirm xf86-video-amdgpu
            ;;
        "intel")
            pacman -S --noconfirm xf86-video-intel
            ;;
        *)
            log_warning "GPU 드라이버를 자동 설치할 수 없음"
            ;;
    esac
    
    log_success "GPU 드라이버 설치 완료"
}

install_applications() {
    local profile=${1:-"beginner"}
    
    log_info "애플리케이션 설치 중: $profile"
    
    case "$profile" in
        "beginner")
            pacman -S --noconfirm firefox libreoffice-still vlc
            ;;
        "developer")
            pacman -S --noconfirm git vim neovim code docker
            ;;
        "gamer")
            pacman -S --noconfirm steam
            ;;
        *)
            log_warning "알 수 없는 프로필: $profile"
            ;;
    esac
    
    log_success "애플리케이션 설치 완료"
}

finalize_installation() {
    log_info "설치 마무리 중..."
    
    # 부트로더 설치
    if [[ "$UEFI_MODE" == true ]]; then
        bootctl --path=/boot install
    else
        pacman -S --noconfirm grub
        grub-install --target=i386-pc /dev/sda
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
    
    # 불필요한 파일 정리
    rm -f /root/unifiedarch-installer
    
    log_success "설치 마무리 완료"
}

# 메인 설치 함수
main() {
    log_info "UnifiedArch OS 설치 시작"
    
    # 설정 로드
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "설정 파일 로드: $CONFIG_FILE"
        # TODO: YAML 설정 파싱
    fi
    
    check_requirements
    detect_hardware
    partition_disk
    mount_filesystems
    install_base_system
    generate_fstab
    chroot_setup
    
    # chroot 단계에서는 아래 함수들이 실행됨
    if [[ "${1:-}" == "chroot_phase" ]]; then
        chroot_phase
        install_desktop_environment "${DESKTOP:-gnome}"
        install_gpu_drivers
        install_applications "${PROFILE:-beginner}"
        finalize_installation
        
        log_success "UnifiedArch OS 설치 완료!"
        log_info "시스템을 재부팅하고 새로운 운영체제를 즐겨보세요."
        exit 0
    fi
}

# 스크립트 실행
main "$@"
