#!/bin/bash
# UnifiedArch OS 실제 설치 스크립트
# 실제로 동작하는 Arch Linux 기반 설치 시스템

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
SCRIPT_NAME="unifiedarch-installer"

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
                                              
    Arch Linux 기반 통합 운영체제
EOF
    echo -e "${NC} 버전: $VERSION"
    echo ""
}

# 시스템 요구사항 확인
check_requirements() {
    log_step "시스템 요구사항 확인 중..."
    
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
    
    # 필수 도구 확인
    local required_tools=("pacman" "pacstrap" "genfstab" "arch-chroot" "timedatectl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "필수 도구를 찾을 수 없음: $tool"
            exit 1
        fi
    done
    
    # UEFI 모드 확인
    if [[ -d /sys/firmware/efi ]]; then
        UEFI_MODE=true
        log_info "UEFI 모드 감지됨"
    else
        UEFI_MODE=false
        log_info "BIOS 모드 감지됨"
    fi
    
    log_success "요구사항 확인 완료"
}

# 하드웨어 감지
detect_hardware() {
    log_step "하드웨어 자동 감지 중..."
    
    # CPU 감지
    CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)
    CPU_CORES=$(nproc)
    log_info "CPU: $CPU_MODEL ($CPU_CORES 코어)"
    
    # 메모리 감지
    MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEMORY_GB=$((MEMORY_KB / 1024 / 1024))
    log_info "메모리: ${MEMORY_GB}GB"
    
    # GPU 감지
    if lspci | grep -i nvidia >/dev/null; then
        GPU_TYPE="nvidia"
        log_info "GPU: NVIDIA 감지됨"
    elif lspci | grep -i amd >/dev/null; then
        GPU_TYPE="amd"
        log_info "GPU: AMD 감지됨"
    elif lspci | grep -i intel >/dev/null; then
        GPU_TYPE="intel"
        log_info "GPU: Intel 감지됨"
    else
        GPU_TYPE="unknown"
        log_warning "GPU를 감지할 수 없음"
    fi
    
    # 저장 장치 감지
    mapfile -t DISKS < <(lsblk -d -o NAME,SIZE | grep -E '^[hs]d|nvme' | awk '{print $1}')
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        log_error "저장 장치를 찾을 수 없습니다."
        exit 1
    fi
    
    log_info "저장 장치:"
    for disk in "${DISKS[@]}"; do
        local size=$(lsblk -d -o SIZE "/dev/$disk" | tail -n1 | xargs)
        log_info "  /dev/$disk ($size)"
    done
    
    # 네트워크 감지
    if ip link show | grep -q "state UP"; then
        NETWORK_AVAILABLE=true
        log_info "네트워크 연결됨"
    else
        NETWORK_AVAILABLE=false
        log_warning "네트워크 연결되지 않음"
    fi
    
    # 노트북 여부 확인
    if [[ -d /sys/class/power_supply/BAT0 ]]; then
        IS_LAPTOP=true
        log_info "노트북으로 감지됨"
    else
        IS_LAPTOP=false
        log_info "데스크톱으로 감지됨"
    fi
    
    log_success "하드웨어 감지 완료"
}

# 사용자 설정 대화식 선택
interactive_setup() {
    log_step "설정 대화식 선택"
    
    # 언어 선택
    echo "언어를 선택하세요:"
    echo "1) 한국어"
    echo "2) English"
    read -p "선택 (1-2): " lang_choice
    
    case $lang_choice in
        1)
            LANG="ko_KR.UTF-8"
            KEYMAP="ko"
            ;;
        2)
            LANG="en_US.UTF-8"
            KEYMAP="us"
            ;;
        *)
            LANG="en_US.UTF-8"
            KEYMAP="us"
            ;;
    esac
    
    # 시간대 선택
    echo "시간대를 선택하세요:"
    echo "1) Asia/Seoul"
    echo "2) UTC"
    read -p "선택 (1-2): " tz_choice
    
    case $tz_choice in
        1)
            TIMEZONE="Asia/Seoul"
            ;;
        2)
            TIMEZONE="UTC"
            ;;
        *)
            TIMEZONE="UTC"
            ;;
    esac
    
    # 사용자 프로필 선택
    echo "사용자 프로필을 선택하세요:"
    echo "1) 초보자 - Windows 사용자"
    echo "2) 일반 사용자 - 데스크톱"
    echo "3) 개발자 - 프로그래밍"
    echo "4) 시스템 관리자 - 서버"
    echo "5) 게이머 - 성능 최적화"
    echo "6) 최소화 - 경량 시스템"
    read -p "선택 (1-6): " profile_choice
    
    case $profile_choice in
        1)
            PROFILE="beginner"
            DESKTOP="gnome"
            ;;
        2)
            PROFILE="general"
            DESKTOP="kde"
            ;;
        3)
            PROFILE="developer"
            DESKTOP="i3"
            ;;
        4)
            PROFILE="administrator"
            DESKTOP="none"
            ;;
        5)
            PROFILE="gamer"
            DESKTOP="gnome"
            ;;
        6)
            PROFILE="minimal"
            DESKTOP="i3"
            ;;
        *)
            PROFILE="beginner"
            DESKTOP="gnome"
            ;;
    esac
    
    # 디스크 선택
    echo "설치할 디스크를 선택하세요:"
    for i in "${!DISKS[@]}"; do
        local size=$(lsblk -d -o SIZE "/dev/${DISKS[$i]}" | tail -n1 | xargs)
        echo "$((i+1))) /dev/${DISKS[$i]} ($size)"
    done
    read -p "선택: " disk_choice
    
    if [[ $disk_choice -ge 1 && $disk_choice -le ${#DISKS[@]} ]]; then
        INSTALL_DISK="${DISKS[$((disk_choice-1))]}"
    else
        INSTALL_DISK="${DISKS[0]}"
    fi
    
    # hostname 설정
    read -p "호스트 이름 (기본: unifiedarch): " hostname_input
    HOSTNAME="${hostname_input:-unifiedarch}"
    
    # 사용자 이름 설정
    read -p "사용자 이름 (기본: user): " username_input
    USERNAME="${username_input:-user}"
    
    log_success "설정 완료"
    log_info "프로필: $PROFILE"
    log_info "데스크톱: $DESKTOP"
    log_info "디스크: /dev/$INSTALL_DISK"
    log_info "호스트 이름: $HOSTNAME"
    log_info "사용자: $USERNAME"
}

# 디스크 파티셔닝
partition_disk() {
    log_step "디스크 파티셔닝 중..."
    
    local disk="/dev/$INSTALL_DISK"
    
    # 기존 파티션 경고
    if [[ -n $(lsblk "$disk" -n -o NAME | tail -n +2) ]]; then
        log_warning "디스크에 기존 파티션이 있습니다."
        read -p "계속하면 모든 데이터가 삭제됩니다. 계속하시겠습니까? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            log_error "설치가 취소되었습니다."
            exit 1
        fi
    fi
    
    # 파티션 테이블 초기화
    wipefs -a "$disk"
    sgdisk --zap-all "$disk" >/dev/null 2>&1
    
    if [[ "$UEFI_MODE" == true ]]; then
        log_info "UEFI 파티셔닝 수행"
        
        # GPT 파티셔닝
        sgdisk "$disk" \
            --new=1:0:+512M --typecode=1:ef00 --change-name=1:"EFI System" \
            --new=2:0:+2G --typecode=2:8200 --change-name=2:"Linux swap" \
            --new=3:0:0 --typecode=3:8300 --change-name=3:"Linux filesystem"
        
        # 파티션 새로고침
        partprobe "$disk"
        sleep 2
        
        # 파티션 변수 설정
        ESP_PARTITION="${disk}1"
        SWAP_PARTITION="${disk}2"
        ROOT_PARTITION="${disk}3"
        
        # 파일 시스템 생성
        mkfs.fat -F32 "$ESP_PARTITION"
        mkswap "$SWAP_PARTITION"
        mkfs.ext4 -F "$ROOT_PARTITION"
        
    else
        log_info "BIOS 파티셔닝 수행"
        
        # MBR 파티셔닝
        sfdisk "$disk" << EOF
,2G,S
,*
EOF
        
        # 파티션 새로고침
        partprobe "$disk"
        sleep 2
        
        # 파티션 변수 설정
        SWAP_PARTITION="${disk}1"
        ROOT_PARTITION="${disk}2"
        
        # 파일 시스템 생성
        mkswap "$SWAP_PARTITION"
        mkfs.ext4 -F "$ROOT_PARTITION"
    fi
    
    log_success "파티셔닝 완료"
}

# 파일 시스템 마운트
mount_filesystems() {
    log_step "파일 시스템 마운트 중..."
    
    # 루트 파티션 마운트
    mount "$ROOT_PARTITION" /mnt
    
    # EFI 파티션 마운트 (UEFI)
    if [[ "$UEFI_MODE" == true ]]; then
        mkdir -p /mnt/boot
        mount "$ESP_PARTITION" /mnt/boot
    fi
    
    # 스왑 활성화
    swapon "$SWAP_PARTITION"
    
    log_success "파일 시스템 마운트 완료"
}

# 기본 시스템 설치
install_base_system() {
    log_step "기본 시스템 설치 중..."
    
    # 미러리스트 최적화 (한국 미러 우선)
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    
    # 한국 미러 추가
    cat > /etc/pacman.d/mirrorlist << 'EOF'
## Korea
Server = https://ftp.kaist.ac.kr/archlinux/$repo/os/$arch
Server = https://mirror.premi.st/archlinux/$repo/os/$arch

## Global
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.evowise.com/archlinux/$repo/os/$arch
EOF
    
    # 패키지 데이터베이스 업데이트
    pacman -Sy
    
    # 기본 시스템 설치
    local base_packages=(
        base
        base-devel
        linux
        linux-firmware
        networkmanager
        bluez
        cups
        pulseaudio
        alsa-utils
        vim
        git
        wget
        curl
    )
    
    # UEFI 부트로더 추가
    if [[ "$UEFI_MODE" == true ]]; then
        base_packages+=(efibootmgr)
    fi
    
    log_info "pacstrap으로 기본 시스템 설치..."
    pacstrap /mnt "${base_packages[@]}"
    
    log_success "기본 시스템 설치 완료"
}

# 시스템 설정
configure_system() {
    log_step "시스템 설정 중..."
    
    # fstab 생성
    genfstab -U /mnt >> /mnt/etc/fstab
    
    # chroot 환경으로 설정 스크립트 복사
    cp "$0" /mnt/root/unifiedarch-installer
    chmod +x /mnt/root/unifiedarch-installer
    
    # chroot 실행
    arch-chroot /mnt /root/unifiedarch-installer chroot_phase \
        "$LANG" "$TIMEZONE" "$HOSTNAME" "$USERNAME" "$PROFILE" "$DESKTOP" "$GPU_TYPE"
}

# chroot 단계 설정
chroot_phase() {
    local lang="$1"
    local timezone="$2"
    local hostname="$3"
    local username="$4"
    local profile="$5"
    local desktop="$6"
    local gpu_type="$7"
    
    log_info "chroot 환경 설정 시작"
    
    # 시간대 설정
    ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    hwclock --systohc
    
    # 로케일 설정
    sed -i 's/#ko_KR.UTF-8/ko_KR.UTF-8/' /etc/locale.gen
    sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
    locale-gen
    echo "LANG=$lang" > /etc/locale.conf
    
    # 호스트네임 설정
    echo "$hostname" > /etc/hostname
    
    # hosts 파일 설정
    cat > /etc/hosts << EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 $hostname.localdomain $hostname
EOF
    
    # Initramfs 생성
    mkinitcpio -P
    
    # 루트 비밀번호 설정
    log_warning "루트 비밀번호를 설정해주세요:"
    passwd
    
    # 사용자 생성
    useradd -m -G wheel,audio,video,storage -s /bin/bash "$username"
    log_warning "$username 사용자 비밀번호를 설정해주세요:"
    passwd "$username"
    
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
    
    # 데스크톱 환경 설치
    install_desktop_environment "$desktop" "$profile"
    
    # GPU 드라이버 설치
    install_gpu_drivers "$gpu_type" "$profile"
    
    # 프로필별 추가 패키지 설치
    install_profile_packages "$profile"
    
    # 부트로더 설치
    install_bootloader
    
    # 설치 스크립트 정리
    rm -f /root/unifiedarch-installer
    
    log_success "chroot 설정 완료"
}

# 데스크톱 환경 설치
install_desktop_environment() {
    local desktop="$1"
    local profile="$2"
    
    log_info "데스크톱 환경 설치: $desktop"
    
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
            # Xorg 기본 패키지
            pacman -S --noconfirm xorg-server xorg-xinit xorg-utils xterm
            ;;
        "none")
            log_info "데스크톱 환경 설치 건너뜀"
            ;;
        *)
            log_error "지원되지 않는 데스크톱 환경: $desktop"
            ;;
    esac
    
    log_success "데스크톱 환경 설치 완료"
}

# GPU 드라이버 설치
install_gpu_drivers() {
    local gpu_type="$1"
    local profile="$2"
    
    log_info "GPU 드라이버 설치 중..."
    
    case "$gpu_type" in
        "nvidia")
            pacman -S --noconfirm nvidia-dkms nvidia-settings nvidia-utils
            # 32비트 라이브러리 (게이밍 프로필인 경우)
            if [[ "$profile" == "gamer" ]]; then
                pacman -S --noconfirm lib32-nvidia-utils
            fi
            ;;
        "amd")
            pacman -S --noconfirm xf86-video-amdgpu mesa
            if [[ "$profile" == "gamer" ]]; then
                pacman -S --noconfirm lib32-mesa
            fi
            ;;
        "intel")
            pacman -S --noconfirm xf86-video-intel mesa
            ;;
        "unknown")
            log_warning "GPU 드라이버를 자동 설치할 수 없음"
            ;;
    esac
    
    log_success "GPU 드라이버 설치 완료"
}

# 프로필별 패키지 설치
install_profile_packages() {
    local profile="$1"
    
    log_info "프로필별 패키지 설치: $profile"
    
    case "$profile" in
        "beginner")
            pacman -S --noconfirm firefox libreoffice-still vlc gnome-tweaks
            ;;
        "general")
            pacman -S --noconfirm firefox libreoffice-fresh vlc kdenlive gimp
            ;;
        "developer")
            pacman -S --noconfirm git vim neovim code docker docker-compose
            pacman -S --noconfirm python python-pip nodejs npm
            ;;
        "administrator")
            pacman -S --noconfirm openssh fail2ban ufw htop iotop
            ;;
        "gamer")
            pacman -S --noconfirm steam gamemode mangohud
            ;;
        "minimal")
            pacman -S --noconfirm vim git curl
            ;;
        *)
            log_warning "알 수 없는 프로필: $profile"
            ;;
    esac
    
    log_success "프로필 패키지 설치 완료"
}

# 부트로더 설치
install_bootloader() {
    log_info "부트로더 설치 중..."
    
    if [[ "$UEFI_MODE" == true ]]; then
        # UEFI 부트로더 설치
        bootctl --path=/boot install
        
        # 부트로더 항목 생성
        cat > /boot/loader/entries/unifiedarch.conf << EOF
title   UnifiedArch OS
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options  root=UUID=$(blkid -s UUID -o value "$ROOT_PARTITION") rw quiet
EOF
        
        # 기본 부트로더 설정
        echo "default unifiedarch" > /boot/loader/loader.conf
        echo "timeout 3" >> /boot/loader/loader.conf
        
    else
        # BIOS 부트로더 설치
        pacman -S --noconfirm grub
        grub-install --target=i386-pc "/dev/$INSTALL_DISK"
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
    
    log_success "부트로더 설치 완료"
}

# 설치 후 마무리
finalize_installation() {
    log_step "설치 마무리 중..."
    
    # 마운트 해제
    umount -R /mnt
    
    # 스왑 비활성화
    swapoff "$SWAP_PARTITION"
    
    log_success "UnifiedArch OS 설치 완료!"
    log_info "이제 시스템을 재부팅하고 새로운 운영체제를 즐겨보세요."
    log_info "재부팅 후 첫 부팅 설정이 시작됩니다."
    
    read -p "지금 재부팅하시겠습니까? (y/N): " reboot_now
    if [[ $reboot_now =~ ^[Yy]$ ]]; then
        reboot
    fi
}

# 메인 함수
main() {
    banner
    
    # 인자 확인
    if [[ "${1:-}" == "chroot_phase" ]]; then
        # chroot 단계
        chroot_phase "$2" "$3" "$4" "$5" "$6" "$7" "$8"
        exit 0
    fi
    
    # 설치 단계
    check_requirements
    detect_hardware
    interactive_setup
    partition_disk
    mount_filesystems
    install_base_system
    configure_system
    finalize_installation
}

# 스크립트 실행
main "$@"
