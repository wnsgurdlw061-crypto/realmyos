#!/usr/bin/env bash
#
# UnifiedArch OS airootfs Customization Script
# 라이브 시스템 커스터마이제이션
#
# 이 스크립트는 archiso가 패키지를 설치한 후 실행됩니다.
#

set -e -u

echo "=========================================="
echo " UnifiedArch OS Live System Setup"
echo "=========================================="

# ========== 사용자 계정 설정 ==========
echo "[1/12] 사용자 계정 설정 중..."

# 기본 사용자 생성
useradd -m -G wheel,video,audio,storage,optical,network,power,lp,scanner -s /bin/bash unifiedarch
echo "unifiedarch:unifiedarch" | chpasswd

# root 비밀번호 설정
echo "root:unifiedarch" | chpasswd

# sudoers 설정
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-wheel-nopasswd
chmod 440 /etc/sudoers.d/10-wheel-nopasswd

# ========== 로케일 설정 ==========
echo "[2/12] 로케일 설정 중..."

# 한국어 및 영어 로케일 활성화
sed -i 's/#ko_KR.UTF-8 UTF-8/ko_KR.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

# 기본 언어 설정
echo "LANG=ko_KR.UTF-8" > /etc/locale.conf
echo "LC_MESSAGES=en_US.UTF-8" >> /etc/locale.conf

# 콘솔 폰트 설정
echo "KEYMAP=us" > /etc/vconsole.conf
echo "FONT=ter-132n" >> /etc/vconsole.conf

# ========== 시간대 설정 ==========
echo "[3/12] 시간대 설정 중..."

ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
echo "Asia/Seoul" > /etc/timezone

# ========== 호스트 이름 설정 ==========
echo "[4/12] 호스트 이름 설정 중..."

echo "unifiedarch-live" > /etc/hostname

cat > /etc/hosts << 'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   unifiedarch-live.localdomain unifiedarch-live
EOF

# ========== 시스템 서비스 활성화 ==========
echo "[5/12] 시스템 서비스 활성화 중..."

# 네트워크
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable iwd

# 디스플레이 매니저
systemctl enable gdm

# 시스템 서비스
systemctl enable haveged
systemctl enable fstrim.timer
systemctl enable cronie

# 파이프와이어 오디오
systemctl --global enable pipewire-pulse

# ========== GNOME 데스크톱 설정 ==========
echo "[6/12] GNOME 데스크톱 설정 중..."

# 기본 테마 설정
mkdir -p /home/unifiedarch/.config
mkdir -p /home/unifiedarch/.local/share/gsettings-schema

# GNOME 기본 설정 (gsettings)
cat > /home/unifiedarch/.config/gnome-initial-setup-done << 'EOF'
yes
EOF

# dconf 설정
mkdir -p /home/unifiedarch/.config/dconf
cat > /home/unifiedarch/.config/dconf/user << 'EOF'
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/gnome/adwaita-day.jpg'
picture-uri-dark='file:///usr/share/backgrounds/gnome/adwaita-night.jpg'

[org/gnome/desktop/interface]
gtk-theme='Adwaita'
icon-theme='Adwaita'
color-scheme='prefer-light'
font-antialiasing='rgba'

[org/gnome/desktop/peripherals/touchpad]
tap-to-click=true
natural-scroll=true
two-finger-scrolling-enabled=true

[org/gnome/desktop/session]
session-name='gnome'

[org/gnome/desktop/screensaver]
lock-enabled=false

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0
power-button-action='suspend'

[org/gnome/shell]
enabled-extensions=['user-theme@gnome-shell-extensions.gcampax.github.com', 'dash-to-dock@micxgx.gmail.com', 'appindicator@ubuntu.com']

[org/gnome/shell/extensions/dash-to-dock]
dock-position='BOTTOM'
dock-fixed=true
dash-max-icon-size=48

[org/gnome/nautilus/preferences]
default-folder-viewer='icon-view'

[org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-423d-a9ea-7b58f6c6d524]
font='Noto Sans Mono 12'
use-system-fonts=false
use-theme-colors=true
EOF

# ========== 설치 프로그램 바로가기 ==========
echo "[7/12] 설치 프로그램 바로가기 생성 중..."

mkdir -p /home/unifiedarch/Desktop

cat > /home/unifiedarch/Desktop/install-unifiedarch.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install UnifiedArch OS
Name[ko]=UnifiedArch OS 설치
Comment=Install UnifiedArch OS to your computer
Comment[ko]=컴퓨터에 UnifiedArch OS를 설치합니다
Exec=pkexec calamares
Icon=system-software-install
Terminal=false
Categories=System;Settings;
StartupNotify=true
X-GNOME-Autostart-enabled=true
EOF

chmod +x /home/unifiedarch/Desktop/install-unifiedarch.desktop

# ========== 도움말 스크립트 ==========
echo "[8/12] 도움말 스크립트 생성 중..."

# 시스템 정보 스크립트
cat > /usr/local/bin/unifiedarch-info << 'EOF'
#!/bin/bash
echo "========================================="
echo "  UnifiedArch OS System Information"
echo "========================================="
echo ""
echo "OS: UnifiedArch OS $(cat /etc/unifiedarch-release 2>/dev/null || echo '1.0.0')"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo ""
echo "CPU: $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)"
echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2}')"
echo "Disk: $(df -h / | tail -n1 | awk '{print $2}')"
echo ""
echo "Network Interfaces:"
ip -br addr show
echo ""
echo "Graphics:"
lspci | grep -i vga | head -n1
echo ""
echo "========================================="
EOF
chmod +x /usr/local/bin/unifiedarch-info

# 도움말 스크립트
cat > /usr/local/bin/unifiedarch-help << 'EOF'
#!/bin/bash
echo "========================================="
echo "  UnifiedArch OS Quick Help"
echo "========================================="
echo ""
echo "설치 방법:"
echo "  1. 바탕화면의 'Install UnifiedArch OS' 아이콘 클릭"
echo "  2. 또는 터미널에서 'sudo calamares' 실행"
echo ""
echo "주요 명령어:"
echo "  unifiedarch-info  - 시스템 정보"
echo "  unifiedarch-help  - 이 도움말"
echo "  unifiedarch-setup - 초기 설정"
echo ""
echo "네트워크 연결:"
echo "  상단 패널의 네트워크 아이콘 클릭"
echo "  또는 'nmcli device wifi connect <SSID> password <password>'"
echo ""
echo "터미널 단축키:"
echo "  Ctrl+Alt+T - 터미널 열기"
echo ""
echo "문서:"
echo "  온라인: https://docs.unifiedarch.org"
echo "  로컬: /usr/share/doc/unifiedarch/"
echo ""
echo "========================================="
EOF
chmod +x /usr/local/bin/unifiedarch-help

# 초기 설정 스크립트
cat > /usr/local/bin/unifiedarch-setup << 'EOF'
#!/bin/bash
echo "========================================="
echo "  UnifiedArch OS Initial Setup"
echo "========================================="
echo ""
echo "하드웨어 감지 중..."
echo ""
echo "CPU: $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)"
echo "GPU: $(lspci | grep -i vga | head -n1 | cut -d: -f3 | xargs)"
echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2}')"
echo ""
echo "네트워크 상태:"
nmcli device status
echo ""
echo "========================================="
echo "설치를 시작하려면:"
echo "  바탕화면의 'Install UnifiedArch OS' 아이콘을 클릭하세요"
echo "========================================="
EOF
chmod +x /usr/local/bin/unifiedarch-setup

# ========== 커널 모듈 설정 ==========
echo "[9/12] 커널 모듈 설정 중..."

# 자동 로드할 모듈
cat > /etc/modules-load.d/unifiedarch.conf << 'EOF'
# UnifiedArch OS 커널 모듈
# 빌드된 모듈이 있을 경우 자동 로드

# 네트워크 및 오디오
snd_hda_intel
snd_hda_codec
snd_hda_core
snd_pcm
snd_timer
snd
soundcore

# 파일 시스템
btrfs
ext4
xfs
f2fs
ntfs3
exfat

# 가상화
vboxguest
vboxsf
vboxvideo
qemu_guest_agent
EOF

# ========== 파이썬 환경 설정 ==========
echo "[10/12] 파이썬 환경 설정 중..."

# pip 설정
mkdir -p /home/unifiedarch/.config/pip
cat > /home/unifiedarch/.config/pip/pip.conf << 'EOF'
[global]
break-system-packages = true
user = true
EOF

# ========== 권한 설정 ==========
echo "[11/12] 권한 설정 중..."

# 사용자 홈 디렉토리 권한
chown -R unifiedarch:unifiedarch /home/unifiedarch
chmod 755 /home/unifiedarch

# ========== 릴리즈 정보 ==========
echo "[12/12] 릴리즈 정보 생성 중..."

cat > /etc/unifiedarch-release << 'EOF'
UnifiedArch OS 1.0.0
Codename: Aurora
Build Date: $(date +%Y-%m-%d)
Architecture: x86_64
Base: Arch Linux
EOF

cat > /etc/os-release << 'EOF'
NAME="UnifiedArch OS"
VERSION="1.0.0 (Aurora)"
ID=unifiedarch
ID_LIKE=arch
PRETTY_NAME="UnifiedArch OS 1.0.0 (Aurora)"
ANSI_COLOR="0;34"
HOME_URL="https://unifiedarch.org"
DOCUMENTATION_URL="https://docs.unifiedarch.org"
SUPPORT_URL="https://community.unifiedarch.org"
BUG_REPORT_URL="https://bugs.unifiedarch.org"
LOGO=unifiedarch-logo
EOF

# ========== 시작 프로그램 설정 ==========
echo "시작 프로그램 설정 중..."

mkdir -p /home/unifiedarch/.config/autostart

cat > /home/unifiedarch/.config/autostart/unifiedarch-welcome.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=UnifiedArch Welcome
Exec=gnome-terminal -- /usr/local/bin/unifiedarch-setup
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# ========== 완료 ==========
echo ""
echo "=========================================="
echo " UnifiedArch OS Live System Setup Complete"
echo "=========================================="

exit 0
