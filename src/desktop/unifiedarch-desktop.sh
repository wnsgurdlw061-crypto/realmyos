#!/bin/bash
# UnifiedArch OS 데스크톱 환경 설정
# 완벽한 GUI 환경 구성

set -euo pipefail

# 버전 정보
VERSION="1.0.0"

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

# 데스크톱 환경 설치
install_desktop_environment() {
    local desktop_type="${1:-gnome}"
    
    log_info "데스크톱 환경 설치: $desktop_type"
    
    case "$desktop_type" in
        "gnome")
            install_gnome_desktop
            ;;
        "kde")
            install_kde_desktop
            ;;
        "xfce")
            install_xfce_desktop
            ;;
        "minimal")
            install_minimal_desktop
            ;;
        *)
            log_error "알 수 없는 데스크톱 타입: $desktop_type"
            return 1
            ;;
    esac
}

# GNOME 데스크톱 설치
install_gnome_desktop() {
    log_info "GNOME 데스크톱 환경 설치 중..."
    
    # 필수 패키지 목록
    local gnome_packages=(
        "gnome-shell"
        "gnome-session"
        "gnome-control-center"
        "gnome-terminal"
        "nautilus"
        "gnome-tweaks"
        "gnome-shell-extensions"
        "gdm"
        "xorg"
        "xorg-server"
        "mesa-utils"
        "network-manager-gnome"
        "gnome-backgrounds"
        "gnome-icon-theme"
        "gnome-themes-extra"
    )
    
    # 패키지 설치
    for package in "${gnome_packages[@]}"; do
        log_info "패키지 설치: $package"
        if command -v apt >/dev/null 2>&1; then
            sudo apt install -y "$package" 2>/dev/null || true
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed "$package" 2>/dev/null || true
        fi
    done
    
    # GDM 활성화
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable gdm 2>/dev/null || true
    fi
    
    log_success "GNOME 데스크톱 설치 완료"
}

# KDE 데스크톱 설치
install_kde_desktop() {
    log_info "KDE Plasma 데스크톱 환경 설치 중..."
    
    local kde_packages=(
        "plasma-desktop"
        "kde-applications"
        "sddm"
        "xorg"
        "xorg-server"
        "mesa-utils"
        "network-manager-plasma"
    )
    
    for package in "${kde_packages[@]}"; do
        log_info "패키지 설치: $package"
        if command -v apt >/dev/null 2>&1; then
            sudo apt install -y "$package" 2>/dev/null || true
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed "$package" 2>/dev/null || true
        fi
    done
    
    # SDDM 활성화
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable sddm 2>/dev/null || true
    fi
    
    log_success "KDE Plasma 데스크톱 설치 완료"
}

# XFCE 데스크톱 설치
install_xfce_desktop() {
    log_info "XFCE 데스크톱 환경 설치 중..."
    
    local xfce_packages=(
        "xfce4"
        "xfce4-goodies"
        "lightdm"
        "xorg"
        "xorg-server"
        "mesa-utils"
        "network-manager-gnome"
    )
    
    for package in "${xfce_packages[@]}"; do
        log_info "패키지 설치: $package"
        if command -v apt >/dev/null 2>&1; then
            sudo apt install -y "$package" 2>/dev/null || true
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed "$package" 2>/dev/null || true
        fi
    done
    
    # LightDM 활성화
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable lightdm 2>/dev/null || true
    fi
    
    log_success "XFCE 데스크톱 설치 완료"
}

# 최소 데스크톱 설치
install_minimal_desktop() {
    log_info "최소 데스크톱 환경 설치 중..."
    
    local minimal_packages=(
        "i3-wm"  # 또는 "i3"
        "i3status"
        "i3lock"
        "dmenu"
        "xorg"
        "xorg-server"
        "xterm"
        "feh"
        "network-manager"
    )
    
    for package in "${minimal_packages[@]}"; do
        log_info "패키지 설치: $package"
        if command -v apt >/dev/null 2>&1; then
            sudo apt install -y "$package" 2>/dev/null || true
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed "$package" 2>/dev/null || true
        fi
    done
    
    log_success "최소 데스크톱 설치 완료"
}

# UnifiedArch OS 테마 적용
apply_unifiedarch_theme() {
    log_info "UnifiedArch OS 테마 적용 중..."
    
    # 테마 디렉토리 생성
    local theme_dir="/usr/share/themes/UnifiedArch"
    local icon_dir="/usr/share/icons/UnifiedArch"
    
    if [[ $EUID -eq 0 ]]; then
        mkdir -p "$theme_dir" "$icon_dir"
        
        # 테마 설정 파일 생성
        cat > "$theme_dir/index.theme" << 'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=UnifiedArch
Comment=UnifiedArch OS Default Theme
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Adwaita
MetacityTheme=Adwaita
IconTheme=Adwaita
CursorTheme=Adwaita
ButtonLayout=close,minimize,maximize:
EOF
        
        # 아이콘 테마 설정
        cat > "$icon_dir/index.theme" << 'EOF'
[Icon Theme]
Name=UnifiedArch
Comment=UnifiedArch OS Icons
Inherits=Adwaita
Directories=48x48/apps,32x32/apps,24x24/apps

[48x48/apps]
Size=48
Context=Applications
Type=Fixed

[32x32/apps]
Size=32
Context=Applications
Type=Fixed

[24x24/apps]
Size=24
Context=Applications
Type=Fixed
EOF
        
        log_success "UnifiedArch 테마 적용 완료"
    else
        log_warning "테마 적용에는 루트 권한이 필요합니다"
    fi
}

# 데스크톱 설정 구성
configure_desktop() {
    log_info "데스크톱 환경 설정 중..."
    
    # GSettings 설정 (GNOME)
    if command -v gsettings >/dev/null 2>&1; then
        # 기본 배경화면 설정
        gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/unifiedarch-default.jpg"
        
        # 다크 테마
        gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
        gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
        
        # 작업 표시줄 설정
        gsettings set org.gnome.desktop.interface show-battery-percentage true
        gsettings set org.gnome.desktop.interface clock-show-weekday true
        
        # 개인 정보 보호
        gsettings set org.gnome.desktop.privacy report-technical-problems false
        gsettings set org.gnome.desktop.privacy send-software-usage-stats false
        
        log_success "GNOME 데스크톱 설정 완료"
    fi
    
    # XFCE 설정
    if [[ -d "$HOME/.config/xfce4" ]]; then
        mkdir -p "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
        
        cat > "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/unifiedarch-default.jpg"/>
          <property name="image-style" type="int" value="5"/>
          <property name="image-show" type="bool" value="true"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
        
        log_success "XFCE 데스크톱 설정 완료"
    fi
}

# 자동 시작 프로그램 설정
setup_autostart() {
    log_info "자동 시작 프로그램 설정 중..."
    
    local autostart_dir="$HOME/.config/autostart"
    mkdir -p "$autostart_dir"
    
    # UnifiedArch OS 모니터 자동 시작
    cat > "$autostart_dir/unifiedarch-monitor.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=UnifiedArch Monitor
Comment=UnifiedArch OS System Monitor
Exec=/opt/unifiedarch/src/tools/system-monitor.sh realtime 60
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;
StartupNotify=false
EOF
    
    # 방화벽 자동 시작 알림
    cat > "$autostart_dir/unifiedarch-security.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=UnifiedArch Security
Comment=UnifiedArch OS Security Monitor
Exec=/opt/unifiedarch/src/tools/emergency-response.sh monitor
Icon=security-high
Terminal=false
Categories=System;Security;
StartupNotify=false
EOF
    
    log_success "자동 시작 프로그램 설정 완료"
}

# 데스크톱 바로가기 생성
create_desktop_shortcuts() {
    log_info "데스크톱 바로가기 생성 중..."
    
    local desktop_dir="$HOME/Desktop"
    mkdir -p "$desktop_dir"
    
    # UnifiedArch OS 설치 프로그램
    cat > "$desktop_dir/UnifiedArch-Install.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=UnifiedArch OS Installer
Comment=Install UnifiedArch OS
Exec=pkexec /opt/unifiedarch/src/installer/install.sh
Icon=system-software-install
Terminal=true
Categories=System;Installation;
EOF
    
    # UnifiedArch OS 제어판
    cat > "$desktop_dir/UnifiedArch-Control.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=UnifiedArch Control Panel
Comment=UnifiedArch OS Control Panel
Exec=gnome-terminal -- /opt/unifiedarch/src/tools/config-manager.sh
Icon=preferences-system
Terminal=false
Categories=System;Settings;
EOF
    
    # UnifiedArch OS 시스템 모니터
    cat > "$desktop_dir/UnifiedArch-Monitor.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=UnifiedArch Monitor
Comment=UnifiedArch OS System Monitor
Exec=gnome-terminal -- /opt/unifiedarch/src/tools/system-monitor.sh info
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;
EOF
    
    # 실행 권한 부여
    chmod +x "$desktop_dir"/*.desktop
    
    log_success "데스크톱 바로가기 생성 완료"
}

# 배경화면 설정
setup_wallpapers() {
    log_info "배경화면 설정 중..."
    
    local wallpaper_dir="/usr/share/backgrounds/unifiedarch"
    
    if [[ $EUID -eq 0 ]]; then
        mkdir -p "$wallpaper_dir"
        
        # 기본 배경화면 생성 (간단한 그라데이션)
        if command -v convert >/dev/null 2>&1; then
            convert -size 1920x1080 gradient:blue-cyan "$wallpaper_dir/unifiedarch-default.jpg" 2>/dev/null || true
            convert -size 1920x1080 gradient:purple-blue "$wallpaper_dir/unifiedarch-dark.jpg" 2>/dev/null || true
        else
            # ImageMagick 없을 경우 간단한 파일 생성
            echo "UnifiedArch OS Wallpaper" > "$wallpaper_dir/unifiedarch-default.txt"
        fi
        
        log_success "배경화면 설정 완료"
    else
        log_warning "배경화면 설정에는 루트 권한이 필요합니다"
    fi
}

# 시스템 서비스 설정
setup_desktop_services() {
    log_info "데스크톱 관련 서비스 설정 중..."
    
    if [[ $EUID -eq 0 ]] && command -v systemctl >/dev/null 2>&1; then
        # NetworkManager 활성화
        systemctl enable NetworkManager 2>/dev/null || true
        
        # Bluetooth 서비스
        systemctl enable bluetooth 2>/dev/null || true
        
        # CUPS 프린터 서비스
        systemctl enable cups 2>/dev/null || true
        
        # 시스템 사운드 서비스
        systemctl enable pulseaudio 2>/dev/null || true
        systemctl enable alsa-state 2>/dev/null || true
        
        log_success "데스크톱 서비스 설정 완료"
    fi
}

# 완전한 데스크톱 환경 설치
install_complete_desktop() {
    local desktop_type="${1:-gnome}"
    
    log_info "완전한 UnifiedArch OS 데스크톱 환경 설치 시작"
    
    # 1. 데스크톱 환경 설치
    install_desktop_environment "$desktop_type"
    
    # 2. UnifiedArch OS 테마 적용
    apply_unifiedarch_theme
    
    # 3. 데스크톱 설정 구성
    configure_desktop
    
    # 4. 자동 시작 프로그램 설정
    setup_autostart
    
    # 5. 데스크톱 바로가기 생성
    create_desktop_shortcuts
    
    # 6. 배경화면 설정
    setup_wallpapers
    
    # 7. 시스템 서비스 설정
    setup_desktop_services
    
    log_success "완전한 UnifiedArch OS 데스크톱 환경 설치 완료!"
    log_info "재부팅 후 새 데스크톱 환경이 적용됩니다"
}

# 데스크톱 환경 테스트
test_desktop_environment() {
    log_info "데스크톱 환경 테스트 중..."
    
    # 설치된 데스크톱 환경 확인
    if command -v gnome-shell >/dev/null 2>&1; then
        log_success "GNOME Shell 설치됨: $(gnome-shell --version 2>/dev/null || echo "버전 정보 없음")"
    fi
    
    if command -v plasmashell >/dev/null 2>&1; then
        log_success "KDE Plasma 설치됨"
    fi
    
    if command -v xfce4-session >/dev/null 2>&1; then
        log_success "XFCE4 설치됨"
    fi
    
    # 디스플레이 서버 확인
    if command -v X >/dev/null 2>&1 || command -v Xorg >/dev/null 2>&1; then
        log_success "X11 서버 설치됨"
    fi
    
    # 그래픽 드라이버 확인
    if lspci | grep -i vga >/dev/null; then
        local gpu_info=$(lspci | grep -i vga | head -1)
        log_success "그래픽 카드: $gpu_info"
    fi
    
    # 디스플레이 관리자 확인
    if command -v gdm >/dev/null 2>&1; then
        log_success "GDM 디스플레이 관리자 설치됨"
    fi
    
    if command -v sddm >/dev/null 2>&1; then
        log_success "SDDM 디스플레이 관리자 설치됨"
    fi
    
    if command -v lightdm >/dev/null 2>&1; then
        log_success "LightDM 디스플레이 관리자 설치됨"
    fi
    
    log_success "데스크톱 환경 테스트 완료"
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 데스크톱 환경 설정"
    echo ""
    echo "사용법: $0 [옵션] [데스크톱 타입]"
    echo ""
    echo "옵션:"
    echo "  install [type]    - 데스크톱 환경 설치"
    echo "  complete [type]   - 완전한 데스크톱 환경 설치"
    echo "  theme            - UnifiedArch 테마 적용"
    echo "  configure        - 데스크톱 설정 구성"
    echo "  shortcuts        - 데스크톱 바로가기 생성"
    echo "  test             - 데스크톱 환경 테스트"
    echo "  help             - 이 도움말 표시"
    echo ""
    echo "데스크톱 타입:"
    echo "  gnome            - GNOME (기본)"
    echo "  kde              - KDE Plasma"
    echo "  xfce             - XFCE4"
    echo "  minimal          - 최소 환경 (i3)"
    echo ""
    echo "예시:"
    echo "  $0 complete gnome  - 완전한 GNOME 환경 설치"
    echo "  $0 install kde    - KDE Plasma 설치"
    echo "  $0 test           - 현재 환경 테스트"
}

# 메인 함수
main() {
    local command="${1:-help}"
    local desktop_type="${2:-gnome}"
    
    case "$command" in
        "install")
            install_desktop_environment "$desktop_type"
            ;;
        "complete")
            install_complete_desktop "$desktop_type"
            ;;
        "theme")
            apply_unifiedarch_theme
            ;;
        "configure")
            configure_desktop
            ;;
        "shortcuts")
            create_desktop_shortcuts
            ;;
        "test")
            test_desktop_environment
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "알 수 없는 명령: $command"
            show_help
            exit 1
            ;;
    esac
}

# 스크립트 실행
main "$@"
