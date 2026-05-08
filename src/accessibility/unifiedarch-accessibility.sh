#!/bin/bash
#
# UnifiedArch OS 접근성 기능
# 장애인 사용자를 위한 접근성 지원
#
# 기능:
# - 화면 읽기 프로그램
# - 확대/축소 기능
# - 키보드 및 마우스 대안
# - 고대비 테마
# - 음성 인식/합성
#

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
ACCESSIBILITY_DIR="/var/lib/unifiedarch/accessibility"
CONFIG_DIR="/etc/unifiedarch/accessibility"
LOG_FILE="/var/log/unifiedarch-accessibility.log"

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

# 로그 함수
log_accessibility() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ACCESSIBILITY: $1" >> "$LOG_FILE"
}

# 루트 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "루트 권한이 필요합니다"
        exit 1
    fi
}

# 디렉토리 생성
create_directories() {
    mkdir -p "$ACCESSIBILITY_DIR" "$CONFIG_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# 접근성 패키지 설치
install_accessibility_packages() {
    log_step "접근성 패키지 설치 중..."
    
    local accessibility_packages=(
        "orca"                 # 화면 읽기 프로그램
        "espeakup"             # 음성 합성
        "festival"             # 음성 합성 시스템
        "brltty"               # 점자 디스플레이 지원
        "gnome-orca"           # GNOME 화면 읽기
        "mousetweaks"          # 마우스 보조 도구
        "onboard"              # 화면 키보드
        "caribou"              # 화면 키보드
        "dasher"               # 예측 텍스트 입력
        "gok"                  # 그래픽 온스크린 키보드
        "eog"                  # 이미지 뷰어 (확대 기능)
        "gnome-mag"            # 화면 확대
        "compiz-fusion-plugins" # 데스크톱 효과
    )
    
    # 패키지 설치
    for package in "${accessibility_packages[@]}"; do
        if ! pacman -Qi "$package" &>/dev/null; then
            log_info "패키지 설치 중: $package"
            pacman -S --needed --noconfirm "$package" 2>/dev/null || log_warning "$package 설치 실패"
        else
            log_info "이미 설치됨: $package"
        fi
    done
    
    log_success "접근성 패키지 설치 완료"
    log_accessibility "접근성 패키지 설치 완료"
}

# 화면 읽기 프로그램 설정
setup_screen_reader() {
    log_step "화면 읽기 프로그램 설정 중..."
    
    # Orca 설정
    if command -v orca &>/dev/null; then
        # Orca 자동 시작 설정
        mkdir -p /etc/xdg/autostart
        cat > /etc/xdg/autostart/orca-autostart.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Orca Screen Reader
Comment=Orca screen reader for GNOME
Exec=orca --no-setup --disable-speech-dispatcher
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
        
        # Orca 기본 설정
        mkdir -p "$CONFIG_DIR/orca"
        cat > "$CONFIG_DIR/orca/orca-settings.py" << 'EOF'
# UnifiedArch OS Orca 기본 설정

import orca.settings

# 음성 설정
orca.settings.speechRate = 50
orca.settings.speechPitch = 50
orca.settings.speechVolume = 80

# 화면 읽기 설정
orca.settings.enableSpeech = True
orca.settings.enableBraille = False
orca.settings.enableBrailleMonitor = False

# 키보드 설정
orca.settings.orcaModifierKeys = ["Insert", "KP_Insert"]
orca.settings.keyboardLayout = "desktop"

# 마우스 설정
orca.settings.enableMouseReview = False
orca.settings.presentToolTips = True

# 애플리케이션 설정
orca.settings.enableProgressBarUpdates = True
orca.settings.enableProgressBarVerbosity = True
EOF
        
        log_success "Orca 화면 읽기 프로그램 설정 완료"
        log_accessibility "Orca 화면 읽기 프로그램 설정"
    fi
    
    # espeakup 설정
    if command -v espeakup &>/dev/null; then
        # espeakup 서비스 설정
        cat > /etc/systemd/system/espeakup.service << 'EOF'
[Unit]
Description=espeakup speech synthesis
After=systemd-udev-settle.service
Wants=sound.target

[Service]
Type=simple
ExecStart=/usr/bin/espeakup
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload 2>/dev/null || log_warning "systemd 데몬 리로드 실패"
        systemctl enable espeakup.service 2>/dev/null || log_warning "espeakup 서비스 활성화 실패"
        
        log_success "espeakup 음성 합성 설정 완료"
        log_accessibility "espeakup 음성 합성 설정"
    fi
}

# 화면 확대 기능 설정
setup_screen_magnifier() {
    log_step "화면 확대 기능 설정 중..."
    
    # GNOME 확대 기능 설정
    if command -v gsettings &>/dev/null; then
        # 확대 기능 활성화
        gsettings set org.gnome.desktop.a11y.applications magnifier-enabled true
        gsettings set org.gnome.desktop.a11y.magnifier mag-factor 2.0
        gsettings set org.gnome.desktop.a11y.magnifier lens-shape "circle"
        gsettings set org.gnome.desktop.a11y.magnifier mouse-tracking "centered"
        gsettings set org.gnome.desktop.a11y.magnifier screen-position "full-screen"
        
        log_success "GNOME 화면 확대 기능 설정 완료"
        log_accessibility "GNOME 화면 확대 기능 설정"
    fi
    
    # Compiz 확대 플러그인 설정
    if command -v compiz &>/dev/null; then
        mkdir -p "$CONFIG_DIR/compiz"
        cat > "$CONFIG_DIR/compiz/magnifier.ini" << 'EOF'
[ezoom]
active_plugins = [ezoom]
s0_active_plugins = [ezoom]
s0_ezoom_zoom_mode = 1
s0_ezoom_zoom_factor = 2.0
s0_ezoom_mouse_tracking = 1
s0_ezoom_filter_linear = true
EOF
        
        log_success "Compiz 확대 기능 설정 완료"
        log_accessibility "Compiz 확대 기능 설정"
    fi
}

# 화면 키보드 설정
setup_on_screen_keyboard() {
    log_step "화면 키보드 설정 중..."
    
    # Onboard 화면 키보드 설정
    if command -v onboard &>/dev/null; then
        # Onboard 자동 시작 설정
        cat > /etc/xdg/autostart/onboard-autostart.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Onboard
Comment=On-screen keyboard
Exec=onboard --show-on-startup
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
        
        # Onboard 기본 설정
        mkdir -p "$CONFIG_DIR/onboard"
        cat > "$CONFIG_DIR/onboard/onboard-settings.json" << 'EOF'
{
    "layout": "Compact",
    "theme": "Classic",
    "size": "small",
    "auto_show": true,
    "show_on_startup": true,
    "dock_settings": {
        "position": "bottom",
        "auto_hide": false
    },
    "keyboard_settings": {
        "sticky_keys": true,
        "slow_keys": true,
        "bounce_keys": true
    }
}
EOF
        
        log_success "Onboard 화면 키보드 설정 완료"
        log_accessibility "Onboard 화면 키보드 설정"
    fi
    
    # Caribou 화면 키보드 설정
    if command -v caribou &>/dev/null; then
        # Caribou 자동 시작 설정
        cat > /etc/xdg/autostart/caribou-autostart.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Caribou
Comment=Caribou on-screen keyboard
Exec=caribou
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
        
        log_success "Caribou 화면 키보드 설정 완료"
        log_accessibility "Caribou 화면 키보드 설정"
    fi
}

# 고대비 테마 설정
setup_high_contrast_theme() {
    log_step "고대비 테마 설정 중..."
    
    # 고대비 테마 패키지 설치
    local theme_packages=(
        "gnome-themes-extra"
        "gnome-icon-theme"
        "adwaita-icon-theme"
    )
    
    for package in "${theme_packages[@]}"; do
        if ! pacman -Qi "$package" &>/dev/null; then
            pacman -S --needed --noconfirm "$package" 2>/dev/null || log_warning "$package 설치 실패"
        fi
    done
    
    # 고대비 테마 설정
    if command -v gsettings &>/dev/null; then
        # GTK 테마 설정
        gsettings set org.gnome.desktop.interface gtk-theme "HighContrast"
        gsettings set org.gnome.desktop.interface icon-theme "HighContrast"
        gsettings set org.gnome.desktop.interface font-name "Sans 12"
        gsettings set org.gnome.desktop.interface monospace-font-name "Monospace 12"
        
        # GNOME 셸 테마 설정
        gsettings set org.gnome.shell.extensions.user-theme name "HighContrast"
        
        # 배경화면 설정
        gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/gnome/HighContrast.jpg"
        gsettings set org.gnome.desktop.background primary-color "#000000"
        gsettings set org.gnome.desktop.background secondary-color "#FFFFFF"
        
        log_success "고대비 테마 설정 완료"
        log_accessibility "고대비 테마 설정"
    fi
    
    # 고대비 아이콘 테마 생성
    mkdir -p /usr/share/icons/HighContrast
    cat > /usr/share/icons/HighContrast/index.theme << 'EOF'
[Icon Theme]
Name=High Contrast
Comment=High contrast theme for accessibility
Inherits=Adwaita
Directories=16x16,22x22,24x24,32x32,48x48,256x256

[16x16]
Size=16
Context=Actions
Type=Scalable

[22x22]
Size=22
Context=Actions
Type=Scalable

[24x24]
Size=24
Context=Actions
Type=Scalable

[32x32]
Size=32
Context=Actions
Type=Scalable

[48x48]
Size=48
Context=Actions
Type=Scalable

[256x256]
Size=256
Context=Actions
Type=Scalable
EOF
    
    log_success "고대비 아이콘 테마 생성 완료"
}

# 키보드 접근성 설정
setup_keyboard_accessibility() {
    log_step "키보드 접근성 설정 중..."
    
    # GNOME 키보드 접근성 설정
    if command -v gsettings &>/dev/null; then
        # 고정 키 (Sticky Keys)
        gsettings set org.gnome.desktop.a11y.keyboard stickykeys-enable true
        gsettings set org.gnome.desktop.a11y.keyboard stickykeys-two-key-off false
        
        # 느린 키 (Slow Keys)
        gsettings set org.gnome.desktop.a11y.keyboard slowkeys-enable true
        gsettings set org.gnome.desktop.a11y.keyboard slowkeys-delay 0.5
        
        # 바운스 키 (Bounce Keys)
        gsettings set org.gnome.desktop.a11y.keyboard bouncekeys-enable true
        gsettings set org.gnome.desktop.a11y.keyboard bouncekeys-delay 0.3
        
        # 마우스 키 (Mouse Keys)
        gsettings set org.gnome.desktop.a11y.keyboard mousekeys-enable true
        gsettings set org.gnome.desktop.a11y.keyboard mousekeys-init-delay 300
        gsettings set org.gnome.desktop.a11y.keyboard mousekeys-max-speed 1000
        gsettings set org.gnome.desktop.a11y.keyboard mousekeys-accel-time 300
        
        log_success "GNOME 키보드 접근성 설정 완료"
        log_accessibility "GNOME 키보드 접근성 설정"
    fi
    
    # X11 키보드 접근성 설정
    if [[ -f "/etc/X11/xorg.conf.d/90-accessibility.conf" ]]; then
        cat > /etc/X11/xorg.conf.d/90-accessibility.conf << 'EOF'
# UnifiedArch OS 접근성 X11 설정

Section "InputClass"
    Identifier "keyboard"
    MatchIsKeyboard "on"
    Option "XkbOptions" "grp:alt_shift_toggle,compose:ralt,ctrl:nocaps"
EndSection

Section "InputClass"
    Identifier "mouse"
    MatchIsPointer "on"
    Option "Emulate3Buttons" "true"
    Option "EmulateWheel" "true"
    Option "EmulateWheelButton" "2"
EndSection
EOF
        
        log_success "X11 키보드 접근성 설정 완료"
        log_accessibility "X11 키보드 접근성 설정"
    fi
}

# 점자 지원 설정
setup_braille_support() {
    log_step "점자 지원 설정 중..."
    
    # BRLTTY 설정
    if command -v brltty &>/dev/null; then
        # BRLTTY 기본 설정
        cat > /etc/brltty.conf << 'EOF'
# UnifiedArch OS BRLTTY 설정

# 점자 디스플레이 드라이버
braille-driver auto

# 텍스트 테이블
text-table en_US

# 점자 테이블
braille-table unicode-brf

# 음성 합성
speech-driver espeak

# 키보드 매핑
keyboard-driver auto

# 디버깅
log-level warning
EOF
        
        # BRLTTY 서비스 설정
        cat > /etc/systemd/system/brltty.service << 'EOF'
[Unit]
Description=Braille Terminal Daemon
After=systemd-udev-settle.service
Wants=sound.target

[Service]
Type=simple
ExecStart=/usr/bin/brltty -f /etc/brltty.conf
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload 2>/dev/null || log_warning "systemd 데몬 리로드 실패"
        systemctl enable brltty.service 2>/dev/null || log_warning "brltty 서비스 활성화 실패"
        
        log_success "점자 지원 설정 완료"
        log_accessibility "점자 지원 설정"
    fi
}

# 음성 인식 설정
setup_voice_recognition() {
    log_step "음성 인식 설정 중..."
    
    # 음성 인식 패키지 설치
    local voice_packages=(
        "speech-dispatcher"
        "python-pyttsx3"
        "python-speechrecognition"
        "julius"
    )
    
    for package in "${voice_packages[@]}"; do
        if ! pacman -Qi "$package" &>/dev/null; then
            pacman -S --needed --noconfirm "$package" 2>/dev/null || log_warning "$package 설치 실패"
        fi
    done
    
    # Speech Dispatcher 설정
    if command -v speech-dispatcher &>/dev/null; then
        cat > /etc/speech-dispatcher/speechd.conf << 'EOF'
# UnifiedArch OS Speech Dispatcher 설정

# 기본 출력 모듈
DefaultModule espeak

# 음성 합성 모듈
AddModule "espeak" "sd_espeak"
AddModule "festival" "sd_festival"

# 음성 설정
DefaultVoiceType "male1"
DefaultVolume 80
DefaultRate 50
DefaultPitch 50

# 로깅
LogLevel 3
LogFile "/var/log/speech-dispatcher.log"
EOF
        
        # Speech Dispatcher 서비스 설정
        cat > /etc/systemd/system/speech-dispatcher.service << 'EOF'
[Unit]
Description=Speech Dispatcher
After=sound.target

[Service]
Type=simple
ExecStart=/usr/bin/speech-dispatcher --spawn
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload 2>/dev/null || log_warning "systemd 데몬 리로드 실패"
        systemctl enable speech-dispatcher.service 2>/dev/null || log_warning "speech-dispatcher 서비스 활성화 실패"
        
        log_success "음성 인식 설정 완료"
        log_accessibility "음성 인식 설정"
    fi
}

# 접근성 프로파일 생성
create_accessibility_profiles() {
    log_step "접근성 프로파일 생성 중..."
    
    # 시각 장애 프로파일
    cat > "$CONFIG_DIR/profiles/visual-impairment.conf" << 'EOF'
# 시각 장애 사용자 프로파일

# 화면 읽기 프로그램
SCREEN_READER=true
SPEECH_RATE=50
SPEECH_VOLUME=80

# 화면 확대
MAGNIFIER=true
MAGNIFICATION_FACTOR=2.0
MOUSE_TRACKING=centered

# 고대비 테마
HIGH_CONTRAST=true
THEME=HighContrast
FONT_SIZE=12

# 키보드 접근성
STICKY_KEYS=true
SLOW_KEYS=true
MOUSE_KEYS=true
EOF
    
    # 청각 장애 프로파일
    cat > "$CONFIG_DIR/profiles/hearing-impairment.conf" << 'EOF'
# 청각 장애 사용자 프로파일

# 시각 알림
VISUAL_ALERTS=true
VISUAL_BELL=true

# 자막
CAPTIONS=true
CAPTION_SIZE=large

# 진동 피드백
HAPTIC_FEEDBACK=true
VIBRATION_INTENSITY=medium

# 시각 알림 설정
FLASH_WINDOW=true
FLASH_SCREEN=false
EOF
    
    # 운동 장애 프로파일
    cat > "$CONFIG_DIR/profiles/motor-impairment.conf" << 'EOF'
# 운동 장애 사용자 프로파일

# 화면 키보드
ON_SCREEN_KEYBOARD=true
KEYBOARD_LAYOUT=compact
AUTO_SHOW=true

# 키보드 접근성
STICKY_KEYS=true
SLOW_KEYS=true
BOUNCE_KEYS=true
SLOW_KEYS_DELAY=0.5

# 마우스 대안
MOUSE_KEYS=true
MOUSE_SPEED=slow
MOUSE_ACCELERATION=low

# 음성 제어
VOICE_CONTROL=true
VOICE_COMMANDS=basic
EOF
    
    # 인지 장애 프로파일
    cat > "$CONFIG_DIR/profiles/cognitive-impairment.conf" << 'EOF'
# 인지 장애 사용자 프로파일

# 단순화된 인터페이스
SIMPLIFIED_UI=true
MINIMAL_DISTRACTIONS=true

# 큰 글자
LARGE_TEXT=true
FONT_SIZE=14
ICON_SIZE=large

# 예측 텍스트
WORD_PREDICTION=true
AUTO_COMPLETE=true

# 가이드 모드
GUIDED_MODE=true
STEP_BY_STEP=true
EOF
    
    log_success "접근성 프로파일 생성 완료"
    log_accessibility "접근성 프로파일 생성"
}

# 접근성 관리자 생성
create_accessibility_manager() {
    log_step "접근성 관리자 생성 중..."
    
    cat > "/usr/local/bin/unifiedarch-accessibility-manager" << 'EOF'
#!/bin/bash
# UnifiedArch OS 접근성 관리자

ACCESSIBILITY_DIR="/var/lib/unifiedarch/accessibility"
CONFIG_DIR="/etc/unifiedarch/accessibility"

show_help() {
    echo "UnifiedArch OS 접근성 관리자"
    echo ""
    echo "사용법: $0 [명령어] [인자]"
    echo ""
    echo "명령어:"
    echo "  enable <기능>      - 접근성 기능 활성화"
    echo "  disable <기능>     - 접근성 기능 비활성화"
    echo "  profile <프로파일> - 접근성 프로파일 적용"
    echo "  status             - 현재 상태 표시"
    echo "  list               - 사용 가능한 기능 목록"
    echo "  help               - 이 도움말"
    echo ""
    echo "기능:"
    echo "  screen-reader      - 화면 읽기 프로그램"
    echo "  magnifier          - 화면 확대"
    echo "  on-screen-keyboard - 화면 키보드"
    echo "  high-contrast      - 고대비 테마"
    echo "  keyboard-access    - 키보드 접근성"
    echo "  braille            - 점자 지원"
    echo "  voice-recognition  - 음성 인식"
}

list_features() {
    echo "사용 가능한 접근성 기능:"
    echo ""
    echo "  screen-reader      - 화면 읽기 프로그램 (Orca)"
    echo "  magnifier          - 화면 확대 기능"
    echo "  on-screen-keyboard - 화면 키보드 (Onboard)"
    echo "  high-contrast      - 고대비 테마"
    echo "  keyboard-access    - 키보드 접근성"
    echo "  braille            - 점자 지원 (BRLTTY)"
    echo "  voice-recognition  - 음성 인식"
}

enable_feature() {
    local feature="$1"
    
    case "$feature" in
        screen-reader)
            if command -v orca &>/dev/null; then
                gsettings set org.gnome.desktop.a11y.applications screen-reader-enabled true
                systemctl start espeakup.service 2>/dev/null
                echo "화면 읽기 프로그램 활성화"
            else
                echo "화면 읽기 프로그램이 설치되지 않음"
                return 1
            fi
            ;;
        magnifier)
            gsettings set org.gnome.desktop.a11y.applications magnifier-enabled true
            echo "화면 확대 기능 활성화"
            ;;
        on-screen-keyboard)
            if command -v onboard &>/dev/null; then
                onboard --show-on-startup &
                echo "화면 키보드 활성화"
            else
                echo "화면 키보드가 설치되지 않음"
                return 1
            fi
            ;;
        high-contrast)
            gsettings set org.gnome.desktop.interface gtk-theme "HighContrast"
            gsettings set org.gnome.desktop.interface icon-theme "HighContrast"
            echo "고대비 테마 활성화"
            ;;
        keyboard-access)
            gsettings set org.gnome.desktop.a11y.keyboard stickykeys-enable true
            gsettings set org.gnome.desktop.a11y.keyboard slowkeys-enable true
            echo "키보드 접근성 활성화"
            ;;
        braille)
            if command -v brltty &>/dev/null; then
                systemctl start brltty.service 2>/dev/null
                echo "점자 지원 활성화"
            else
                echo "점자 지원이 설치되지 않음"
                return 1
            fi
            ;;
        voice-recognition)
            if command -v speech-dispatcher &>/dev/null; then
                systemctl start speech-dispatcher.service 2>/dev/null
                echo "음성 인식 활성화"
            else
                echo "음성 인식이 설치되지 않음"
                return 1
            fi
            ;;
        *)
            echo "알 수 없는 기능: $feature"
            return 1
            ;;
    esac
}

disable_feature() {
    local feature="$1"
    
    case "$feature" in
        screen-reader)
            gsettings set org.gnome.desktop.a11y.applications screen-reader-enabled false
            systemctl stop espeakup.service 2>/dev/null
            echo "화면 읽기 프로그램 비활성화"
            ;;
        magnifier)
            gsettings set org.gnome.desktop.a11y.applications magnifier-enabled false
            echo "화면 확대 기능 비활성화"
            ;;
        on-screen-keyboard)
            pkill -f onboard
            echo "화면 키보드 비활성화"
            ;;
        high-contrast)
            gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
            gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
            echo "고대비 테마 비활성화"
            ;;
        keyboard-access)
            gsettings set org.gnome.desktop.a11y.keyboard stickykeys-enable false
            gsettings set org.gnome.desktop.a11y.keyboard slowkeys-enable false
            echo "키보드 접근성 비활성화"
            ;;
        braille)
            systemctl stop brltty.service 2>/dev/null
            echo "점자 지원 비활성화"
            ;;
        voice-recognition)
            systemctl stop speech-dispatcher.service 2>/dev/null
            echo "음성 인식 비활성화"
            ;;
        *)
            echo "알 수 없는 기능: $feature"
            return 1
            ;;
    esac
}

apply_profile() {
    local profile="$1"
    local profile_file="$CONFIG_DIR/profiles/$profile.conf"
    
    if [[ ! -f "$profile_file" ]]; then
        echo "프로파일을 찾을 수 없음: $profile"
        return 1
    fi
    
    echo "프로파일 적용 중: $profile"
    
    # 프로파일 설정 적용
    while IFS= read -r line; do
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            local key=$(echo "$line" | cut -d= -f1)
            local value=$(echo "$line" | cut -d= -f2)
            
            case "$key" in
                SCREEN_READER)
                    if [[ "$value" == "true" ]]; then
                        enable_feature screen-reader
                    else
                        disable_feature screen-reader
                    fi
                    ;;
                MAGNIFIER)
                    if [[ "$value" == "true" ]]; then
                        enable_feature magnifier
                    else
                        disable_feature magnifier
                    fi
                    ;;
                HIGH_CONTRAST)
                    if [[ "$value" == "true" ]]; then
                        enable_feature high-contrast
                    else
                        disable_feature high-contrast
                    fi
                    ;;
                STICKY_KEYS)
                    if [[ "$value" == "true" ]]; then
                        gsettings set org.gnome.desktop.a11y.keyboard stickykeys-enable true
                    else
                        gsettings set org.gnome.desktop.a11y.keyboard stickykeys-enable false
                    fi
                    ;;
            esac
        fi
    done < "$profile_file"
    
    echo "프로파일 적용 완료: $profile"
}

show_status() {
    echo "접근성 기능 상태:"
    echo ""
    
    # 화면 읽기 프로그램
    local screen_reader=$(gsettings get org.gnome.desktop.a11y.applications screen-reader-enabled 2>/dev/null || echo "false")
    echo "화면 읽기 프로그램: $screen_reader"
    
    # 화면 확대
    local magnifier=$(gsettings get org.gnome.desktop.a11y.applications magnifier-enabled 2>/dev/null || echo "false")
    echo "화면 확대: $magnifier"
    
    # 고대비 테마
    local theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "Adwaita")
    echo "테마: $theme"
    
    # 키보드 접근성
    local sticky_keys=$(gsettings get org.gnome.desktop.a11y.keyboard stickykeys-enable 2>/dev/null || echo "false")
    echo "고정 키: $sticky_keys"
    
    # 서비스 상태
    echo ""
    echo "서비스 상태:"
    echo "espeakup: $(systemctl is-active espeakup.service 2>/dev/null || echo "비활성")"
    echo "brltty: $(systemctl is-active brltty.service 2>/dev/null || echo "비활성")"
    echo "speech-dispatcher: $(systemctl is-active speech-dispatcher.service 2>/dev/null || echo "비활성")"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    case "$action" in
        enable)
            enable_feature "$2"
            ;;
        disable)
            disable_feature "$2"
            ;;
        profile)
            apply_profile "$2"
            ;;
        status)
            show_status
            ;;
        list)
            list_features
            ;;
        help)
            show_help
            ;;
        *)
            echo "알 수 없는 명령어: $action"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
EOF
    
    chmod +x "/usr/local/bin/unifiedarch-accessibility-manager"
    
    log_success "접근성 관리자 생성 완료"
    log_accessibility "접근성 관리자 생성"
}

# 도움말
show_help() {
    echo "UnifiedArch OS 접근성 기능"
    echo ""
    echo "사용법: $0 [명령어]"
    echo ""
    echo "명령어:"
    echo "  install-packages    - 접근성 패키지 설치"
    echo "  setup-screen-reader - 화면 읽기 프로그램 설정"
    echo "  setup-magnifier     - 화면 확대 기능 설정"
    echo "  setup-keyboard      - 화면 키보드 설정"
    echo "  setup-contrast      - 고대비 테마 설정"
    echo "  setup-braille       - 점자 지원 설정"
    echo "  setup-voice         - 음성 인식 설정"
    echo "  create-profiles     - 접근성 프로파일 생성"
    echo "  create-manager      - 접근성 관리자 생성"
    echo "  setup-all           - 전체 접근성 기능 설정"
    echo "  help                - 이 도움말"
    echo ""
    echo "접근성 기능:"
    echo "  - 화면 읽기 프로그램 (Orca, espeakup)"
    echo "  - 화면 확대 기능 (GNOME Magnifier, Compiz)"
    echo "  - 화면 키보드 (Onboard, Caribou)"
    echo "  - 고대비 테마"
    echo "  - 키보드 접근성 (고정 키, 느린 키)"
    echo "  - 점자 지원 (BRLTTY)"
    echo "  - 음성 인식/합성 (Speech Dispatcher)"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    check_root
    create_directories
    
    case "$action" in
        install-packages)
            install_accessibility_packages
            ;;
        setup-screen-reader)
            setup_screen_reader
            ;;
        setup-magnifier)
            setup_screen_magnifier
            ;;
        setup-keyboard)
            setup_on_screen_keyboard
            ;;
        setup-contrast)
            setup_high_contrast_theme
            ;;
        setup-braille)
            setup_braille_support
            ;;
        setup-voice)
            setup_voice_recognition
            ;;
        create-profiles)
            create_accessibility_profiles
            ;;
        create-manager)
            create_accessibility_manager
            ;;
        setup-all)
            install_accessibility_packages
            setup_screen_reader
            setup_screen_magnifier
            setup_on_screen_keyboard
            setup_high_contrast_theme
            setup_keyboard_accessibility
            setup_braille_support
            setup_voice_recognition
            create_accessibility_profiles
            create_accessibility_manager
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
