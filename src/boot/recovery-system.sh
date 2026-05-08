#!/bin/bash
#
# UnifiedArch OS Recovery System
# 복구 모드 및 응급 복구 시스템
#
# 기능:
# - single-user mode 자동 설정
# - rescue shell 환경
# - fsck 자동 실행
# - 시스템 진단 도구
# - 네트워크 복구 지원
#

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECOVERY_DIR="/usr/lib/unifiedarch/recovery"
RECOVERY_SCRIPTS="/usr/local/bin"
LOG_FILE="/var/log/unifiedarch-recovery.log"

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
log_recovery() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 복구 환경 확인
check_recovery_environment() {
    log_step "복구 환경 확인 중..."
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "루트 권한이 필요합니다"
        exit 1
    fi
    
    # 시스템 상태 확인
    local boot_mode="normal"
    if [[ "$(systemctl is-system-running 2>/dev/null)" == "degraded" ]]; then
        boot_mode="degraded"
    elif [[ "$(systemctl is-system-running 2>/dev/null)" == "emergency" ]]; then
        boot_mode="emergency"
    fi
    
    echo "$boot_mode"
}

# single-user mode 설정
setup_single_user_mode() {
    log_step "single-user mode 설정 중..."
    
    # systemd-sulogin 설정
    mkdir -p /etc/systemd/system/rescue.service.d
    
    cat > /etc/systemd/system/rescue.service.d/unifiedarch.conf << 'EOF'
[Service]
# UnifiedArch OS 복구 모드 설정
Environment=SYSTEMD_SULOGIN_FORCE=1
Environment=SYSTEMD_LOG_LEVEL=debug

# 네트워크 활성화
ExecStartPre=/usr/local/bin/unifiedarch-recovery-network

# 파일시스템 자동 검사
ExecStartPre=/usr/local/bin/unifiedarch-fsck-auto

# 복구 스크립트
ExecStartPre=/usr/local/bin/unifiedarch-recovery-welcome

# 쉘 환경 설정
Environment=TERM=xterm-256color
Environment=PS1="[RECOVERY] \u@\h:\w\$ "
EOF
    
    log_success "single-user mode 설정 완료"
}

# rescue shell 설정
setup_rescue_shell() {
    log_step "rescue shell 설정 중..."
    
    # emergency 모드 설정
    mkdir -p /etc/systemd/system/emergency.service.d
    
    cat > /etc/systemd/system/emergency.service.d/unifiedarch.conf << 'EOF'
[Service]
# UnifiedArch OS Emergency 모드 설정
Environment=SYSTEMD_EMERGENCY_SERVICE=1
Environment=SYSTEMD_LOG_LEVEL=debug

# 응급 복구 스크립트
ExecStartPre=/usr/local/bin/unifiedarch-emergency-setup

# 필수 서비스 시작
ExecStartPre=/usr/local/bin/unifiedarch-emergency-services

# 쉘 환경
Environment=TERM=xterm-256color
Environment=PS1="[EMERGENCY] \u@\h:\w\$ "
EOF
    
    log_success "rescue shell 설정 완료"
}

# 파일시스템 자동 검사 스크립트
create_fsck_auto() {
    log_step "파일시스템 자동 검사 스크립트 생성 중..."
    
    cat > "$RECOVERY_SCRIPTS/unifiedarch-fsck-auto" << 'EOF'
#!/bin/bash
# UnifiedArch OS 파일시스템 자동 검사

echo "파일시스템 자동 검사 시작..."
log_recovery "파일시스템 자동 검사 시작"

# 루트 파일시스템 확인
root_fs=$(findmnt -n -o FSTYPE /)
root_device=$(findmnt -n -o SOURCE /)

echo "루트 파일시스템: $root_fs ($root_device)"

# 읽기/쓰기로 리마운트
mount -o remount,rw / 2>/dev/null || {
    echo "루트 파일시스템 리마운트 실패"
    log_recovery "루트 파일시스템 리마운트 실패"
    exit 1
}

# 파일시스템 검사
case "$root_fs" in
    ext4)
        echo "ext4 파일시스템 검사 중..."
        fsck -f -y "$root_device" 2>/dev/null || true
        ;;
    btrfs)
        echo "btrfs 파일시스템 검사 중..."
        btrfs scrub start "$root_device" 2>/dev/null || true
        btrfs check "$root_device" 2>/dev/null || true
        ;;
    xfs)
        echo "xfs 파일시스템 검사 중..."
        xfs_repair -y "$root_device" 2>/dev/null || true
        ;;
    *)
        echo "알 수 없는 파일시스템: $root_fs"
        ;;
esac

echo "파일시스템 검사 완료"
log_recovery "파일시스템 검사 완료"
EOF
    
    chmod +x "$RECOVERY_SCRIPTS/unifiedarch-fsck-auto"
    log_success "파일시스템 자동 검사 스크립트 생성 완료"
}

# 네트워크 복구 스크립트
create_recovery_network() {
    log_step "네트워크 복구 스크립트 생성 중..."
    
    cat > "$RECOVERY_SCRIPTS/unifiedarch-recovery-network" << 'EOF'
#!/bin/bash
# UnifiedArch OS 복구 모드 네트워크 설정

echo "네트워크 복구 설정 시작..."
log_recovery "네트워크 복구 설정 시작"

# 필수 모듈 로드
modprobe af_packet 2>/dev/null || true
modprobe unix 2>/dev/null || true

# 네트워크 인터페이스 확인
interfaces=$(ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' ')

echo "네트워크 인터페이스:"
for iface in $interfaces; do
    if [[ "$iface" != "lo" ]]; then
        echo "  $iface"
        ip link set "$iface" up 2>/dev/null || true
    fi
done

# DHCP 시도
if command -v dhclient &>/dev/null; then
    echo "DHCP 주소 요청 중..."
    dhclient -v 2>/dev/null || true
elif command -v dhcpcd &>/dev/null; then
    echo "dhcpcd 시작 중..."
    dhcpcd -k 2>/dev/null || true
    dhcpcd 2>/dev/null || true
fi

# 네트워크 상태 확인
echo ""
echo "네트워크 상태:"
ip addr show 2>/dev/null || echo "네트워크 정보 확인 실패"

echo ""
echo "연결 테스트:"
if ping -c 1 8.8.8.8 &>/dev/null; then
    echo "  인터넷 연결: 정상"
    log_recovery "인터넷 연결 정상"
else
    echo "  인터넷 연결: 실패"
    log_recovery "인터넷 연결 실패"
fi

echo "네트워크 복구 설정 완료"
log_recovery "네트워크 복구 설정 완료"
EOF
    
    chmod +x "$RECOVERY_SCRIPTS/unifiedarch-recovery-network"
    log_success "네트워크 복구 스크립트 생성 완료"
}

# 복구 환영 스크립트
create_recovery_welcome() {
    log_step "복구 환영 스크립트 생성 중..."
    
    cat > "$RECOVERY_SCRIPTS/unifiedarch-recovery-welcome" << 'EOF'
#!/bin/bash
# UnifiedArch OS 복구 모드 환영

clear
echo "================================================================"
echo "           UnifiedArch OS 복구 모드"
echo "================================================================"
echo ""
echo "시스템이 복구 모드로 부팅되었습니다."
echo "시스템 진단 및 복구를 위해 다음 명령어를 사용하세요:"
echo ""
echo "기본 진단:"
echo "  unifiedarch-diagnose      - 전체 시스템 진단"
echo "  unifiedarch-logs          - 로그 분석"
echo "  unifiedarch-network       - 네트워크 상태"
echo "  unifiedarch-services     - 서비스 상태"
echo ""
echo "파일시스템:"
echo "  fsck -f /dev/sdaX         - 파일시스템 검사"
echo "  mount -o remount,rw /     - 루트 쓰기 모드"
echo "  btrfs check /dev/sdaX     - Btrfs 검사"
echo ""
echo "시스템 복구:"
echo "  systemctl isolate multi-user.target  - 다중 사용자 모드"
echo "  systemctl default          - 정상 부팅"
echo "  reboot                    - 시스템 재시작"
echo ""
echo "도움말:"
echo "  unifiedarch-help           - 복구 도움말"
echo ""
echo "================================================================"

# 시스템 정보 표시
echo ""
echo "시스템 정보:"
echo "  커널: $(uname -r)"
echo "  부팅 시간: $(uptime -s)"
echo "  루트 파일시스템: $(findmnt -n -o FSTYPE /)"
echo "  메모리: $(free -h | grep '^Mem:' | awk '{print $2}')"
echo ""

# 로그 기록
log_recovery "복구 모드 진입"
EOF
    
    chmod +x "$RECOVERY_SCRIPTS/unifiedarch-recovery-welcome"
    log_success "복구 환영 스크립트 생성 완료"
}

# 응급 모드 설정 스크립트
create_emergency_setup() {
    log_step "응급 모드 설정 스크립트 생성 중..."
    
    cat > "$RECOVERY_SCRIPTS/unifiedarch-emergency-setup" << 'EOF'
#!/bin/bash
# UnifiedArch OS Emergency 모드 설정

clear
echo "================================================================"
echo "           UnifiedArch OS Emergency 모드"
echo "================================================================"
echo ""
echo "심각한 시스템 오류가 발생했습니다!"
echo ""
echo "즉시 수행해야 할 작업:"
echo ""
echo "1. 파일시스템 마운트:"
echo "   mount -o remount,rw /"
echo ""
echo "2. 파일시스템 검사:"
echo "   fsck -f /dev/sdaX"
echo ""
echo "3. 로그 확인:"
echo "   journalctl -p err -b"
echo ""
echo "4. 시스템 진단:"
echo "   unifiedarch-emergency-diagnose"
echo ""
echo "경고: 데이터 손실이 있을 수 있습니다."
echo "================================================================"

# 응급 진단
echo ""
echo "응급 진단:"
echo "  루트 마운트: $(mount | grep 'on / ' | awk '{print $1}')"
echo "  읽기/쓰기: $(touch /tmp/test 2>/dev/null && echo "가능" || echo "불가능")"
echo "  마운트 공간: $(df -h / | tail -n1 | awk '{print $4}')"

# 로그 기록
log_recovery "Emergency 모드 진입"
EOF
    
    chmod +x "$RECOVERY_SCRIPTS/unifiedarch-emergency-setup"
    log_success "응급 모드 설정 스크립트 생성 완료"
}

# 시스템 진단 도구
create_diagnose_tool() {
    log_step "시스템 진단 도구 생성 중..."
    
    cat > "$RECOVERY_SCRIPTS/unifiedarch-diagnose" << 'EOF'
#!/bin/bash
# UnifiedArch OS 시스템 진단 도구

echo "================================================================"
echo "           UnifiedArch OS 시스템 진단"
echo "================================================================"
echo ""

# 부팅 정보
echo "=== 부팅 정보 ==="
echo "부팅 시간: $(uptime -s)"
echo "커널: $(uname -r)"
echo "부팅 모드: $(systemctl is-system-running 2>/dev/null || echo "알 수 없음")"
echo ""

# 파일시스템 상태
echo "=== 파일시스템 상태 ==="
df -h | grep -E '^/dev/'
echo ""
mount | grep -E '^/dev/' | while read line; do
    device=$(echo "$line" | awk '{print $1}')
    mountpoint=$(echo "$line" | awk '{print $3}')
    echo "$mountpoint: $(findmnt -n -o FSTYPE "$device")"
done
echo ""

# 메모리 상태
echo "=== 메모리 상태 ==="
free -h
echo ""

# 프로세스 상태
echo "=== 프로세스 상태 ==="
ps aux | head -10
echo "총 프로세스: $(ps aux | wc -l)"
echo ""

# 서비스 상태
echo "=== 서비스 상태 ==="
systemctl list-units --failed 2>/dev/null | head -5
echo "실패 서비스: $(systemctl list-units --failed 2>/dev/null | wc -l)"
echo ""

# 네트워크 상태
echo "=== 네트워크 상태 ==="
ip addr show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' '
echo ""
if ping -c 1 8.8.8.8 &>/dev/null; then
    echo "인터넷 연결: 정상"
else
    echo "인터넷 연결: 실패"
fi
echo ""

# 로그 오류
echo "=== 최근 오류 로그 ==="
journalctl -p err -n 5 --no-pager 2>/dev/null || echo "로그 확인 실패"
echo ""

# 하드웨어 정보
echo "=== 하드웨어 정보 ==="
echo "CPU: $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)"
echo "메모리: $(free -h | grep '^Mem:' | awk '{print $2}')"
echo "디스크: $(lsblk | grep -E '^disk' | wc -l)개"
echo ""

echo "================================================================"
log_recovery "시스템 진단 실행"
EOF
    
    chmod +x "$RECOVERY_SCRIPTS/unifiedarch-diagnose"
    log_success "시스템 진단 도구 생성 완료"
}

# 로그 분석 도구
create_log_analyzer() {
    log_step "로그 분석 도구 생성 중..."
    
    cat > "$RECOVERY_SCRIPTS/unifiedarch-logs" << 'EOF'
#!/bin/bash
# UnifiedArch OS 로그 분석 도구

echo "================================================================"
echo "           UnifiedArch OS 로그 분석"
echo "================================================================"
echo ""

# 부팅 로그
echo "=== 부팅 로그 (최근 20줄) ==="
journalctl -b 0 -n 20 --no-pager 2>/dev/null || echo "부팅 로그 확인 실패"
echo ""

# 오류 로그
echo "=== 오류 로그 (최근 10개) ==="
journalctl -p err -n 10 --no-pager 2>/dev/null || echo "오류 로그 확인 실패"
echo ""

# 경고 로그
echo "=== 경고 로그 (최근 10개) ==="
journalctl -p warning -n 10 --no-pager 2>/dev/null || echo "경고 로그 확인 실패"
echo ""

# 커널 로그
echo "=== 커널 로그 (최근 10개) ==="
dmesg | tail -10 2>/dev/null || echo "커널 로그 확인 실패"
echo ""

# 서비스 실패
echo "=== 서비스 실패 로그 ==="
systemctl list-units --failed 2>/dev/null || echo "서비스 상태 확인 실패"
echo ""

# 패키지 설치 로그
if command -v pacman &>/dev/null; then
    echo "=== 패키지 설치 로그 (최근 5개) ==="
    grep -E "pacman.*installed" /var/log/pacman.log 2>/dev/null | tail -5 || echo "패키지 로그 없음"
fi
echo ""

# 복구 로그
echo "=== 복구 로그 (최근 10개) ==="
if [[ -f "/var/log/unifiedarch-recovery.log" ]]; then
    tail -10 /var/log/unifiedarch-recovery.log
else
    echo "복구 로그 없음"
fi

echo "================================================================"
log_recovery "로그 분석 실행"
EOF
    
    chmod +x "$RECOVERY_SCRIPTS/unifiedarch-logs"
    log_success "로그 분석 도구 생성 완료"
}

# 복구 도움말
create_recovery_help() {
    log_step "복구 도움말 생성 중..."
    
    cat > "$RECOVERY_SCRIPTS/unifiedarch-help" << 'EOF'
#!/bin/bash
# UnifiedArch OS 복구 도움말

echo "================================================================"
echo "           UnifiedArch OS 복구 도움말"
echo "================================================================"
echo ""
echo "=== 복구 모드 명령어 ==="
echo ""
echo "기본 명령어:"
echo "  unifiedarch-diagnose    - 시스템 진단"
echo "  unifiedarch-logs        - 로그 분석"
echo "  unifiedarch-network     - 네트워크 설정"
echo "  unifiedarch-services    - 서비스 상태"
echo "  unifiedarch-help        - 이 도움말"
echo ""
echo "파일시스템 명령어:"
echo "  fsck -f /dev/sdaX       - 파일시스템 검사"
echo "  mount -o remount,rw /   - 루트 쓰기 모드"
echo "  umount /dev/sdaX        - 파일시스템 마운트 해제"
echo "  mount /dev/sdaX /mnt    - 파일시스템 마운트"
echo ""
echo "Btrfs 명령어:"
echo "  btrfs check /dev/sdaX    - Btrfs 검사"
echo "  btrfs scrub start /     - Btrfs 스크럽"
echo "  btrfs device stats /     - Btrfs 장치 통계"
echo ""
echo "시스템 명령어:"
echo "  systemctl isolate multi-user.target  - 다중 사용자 모드"
echo "  systemctl default        - 정상 부팅"
echo "  systemctl reboot        - 재부팅"
echo "  systemctl poweroff      - 종료"
echo ""
echo "네트워크 명령어:"
echo "  ip addr show             - 네트워크 인터페이스"
echo "  ip link set eth0 up     - 인터페이스 활성화"
echo "  dhclient                 - DHCP 클라이언트"
echo "  ping 8.8.8.8            - 연결 테스트"
echo ""
echo "=== 일반적인 복구 절차 ==="
echo ""
echo "1. 파일시스템 문제:"
echo "   mount -o remount,rw /"
echo "   fsck -f /dev/sdaX"
echo "   reboot"
echo ""
echo "2. 부팅 실패:"
echo "   unifiedarch-diagnose"
echo "   unifiedarch-logs"
echo "   systemctl isolate multi-user.target"
echo ""
echo "3. 네트워크 문제:"
echo "   unifiedarch-network"
echo "   ip addr show"
echo "   dhclient"
echo ""
echo "4. 서비스 문제:"
echo "   systemctl status <service>"
echo "   journalctl -u <service>"
echo "   systemctl restart <service>"
echo ""
echo "=== 응급 상황 ==="
echo ""
echo "시스템이 응급 모드일 때:"
echo "1. 파일시스템 마운트: mount -o remount,rw /"
echo "2. 로그 확인: journalctl -p err -b"
echo "3. 진단 실행: unifiedarch-emergency-diagnose"
echo "4. 복구 시도: 필요한 조치 수행"
echo ""
echo "================================================================"
EOF
    
    chmod +x "$RECOVERY_SCRIPTS/unifiedarch-help"
    log_success "복구 도움말 생성 완료"
}

# 복구 시스템 설치
install_recovery_system() {
    log_step "복구 시스템 설치 중..."
    
    # 디렉토리 생성
    mkdir -p "$RECOVERY_DIR" "$RECOVERY_SCRIPTS"
    
    # 모든 스크립트 생성
    create_fsck_auto
    create_recovery_network
    create_recovery_welcome
    create_emergency_setup
    create_diagnose_tool
    create_log_analyzer
    create_recovery_help
    
    # 로그 파일 생성
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log_success "복구 시스템 설치 완료"
}

# 복구 시스템 테스트
test_recovery_system() {
    log_step "복구 시스템 테스트 중..."
    
    # 스크립트 실행 가능성 확인
    local scripts=(
        "unifiedarch-fsck-auto"
        "unifiedarch-recovery-network"
        "unifiedarch-recovery-welcome"
        "unifiedarch-diagnose"
        "unifiedarch-logs"
        "unifiedarch-help"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$RECOVERY_SCRIPTS/$script" ]]; then
            if "$RECOVERY_SCRIPTS/$script" --test &>/dev/null; then
                log_success "$script: 정상"
            else
                log_warning "$script: 경고"
            fi
        else
            log_error "$script: 없음"
        fi
    done
    
    log_success "복구 시스템 테스트 완료"
}

# 도움말
show_help() {
    echo "UnifiedArch OS Recovery System"
    echo ""
    echo "사용법: $0 [명령어]"
    echo ""
    echo "명령어:"
    echo "  install          - 복구 시스템 설치"
    echo "  setup-single     - single-user mode 설정"
    echo "  setup-rescue     - rescue shell 설정"
    echo "  test             - 복구 시스템 테스트"
    echo "  diagnose         - 시스템 진단"
    echo "  logs             - 로그 분석"
    echo "  help             - 이 도움말"
    echo ""
    echo "복구 모드 진입 방법:"
    echo "  1. 부팅 시 'e' 키로 GRUB 메뉴 편집"
    echo "  2. 커널 파라미터에 'systemd.unit=rescue.target' 추가"
    echo "  3. Ctrl+X 또는 F10으로 부팅"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    case "$action" in
        install)
            install_recovery_system
            setup_single_user_mode
            setup_rescue_shell
            ;;
        setup-single)
            setup_single_user_mode
            ;;
        setup-rescue)
            setup_rescue_shell
            ;;
        test)
            test_recovery_system
            ;;
        diagnose)
            "$RECOVERY_SCRIPTS/unifiedarch-diagnose"
            ;;
        logs)
            "$RECOVERY_SCRIPTS/unifiedarch-logs"
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
