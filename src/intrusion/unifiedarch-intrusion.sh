#!/bin/bash
#
# UnifiedArch OS Intrusion Detection System
# 침해 대응 시스템
#
# 기능:
# - 실시간 침해 감지
# - 루트키트 탐지
# - 보안 감사
# - 자동 대응 조치
#

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
INTRUSION_DIR="/var/lib/unifiedarch/intrusion"
AUDIT_DIR="/var/lib/unifiedarch/audit"
QUARANTINE_DIR="/var/lib/unifiedarch/quarantine"
LOG_FILE="/var/log/unifiedarch-intrusion.log"
ALERT_FILE="/var/lib/unifiedarch/alerts.log"

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
log_intrusion() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INTRUSION: $1" >> "$LOG_FILE"
}

# 알림 함수
send_alert() {
    local severity="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$severity] $message" >> "$ALERT_FILE"
    
    # 시스템 로그에 기록
    logger -t "unifiedarch-intrusion" "[$severity] $message"
    
    # 심각한 경우 즉시 알림
    if [[ "$severity" == "CRITICAL" ]]; then
        # 데스크톱 알림
        if command -v notify-send &>/dev/null; then
            notify-send -u critical "UnifiedArch OS 보안 경고" "$message"
        fi
        
        # 이메일 알림 (설정된 경우)
        if [[ -n "${ADMIN_EMAIL:-}" ]]; then
            echo "$message" | mail -s "UnifiedArch OS 보안 경고" "$ADMIN_EMAIL" 2>/dev/null || true
        fi
    fi
    
    log_intrusion "ALERT: [$severity] $message"
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
    mkdir -p "$INTRUSION_DIR" "$AUDIT_DIR" "$QUARANTINE_DIR"
    mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$ALERT_FILE")"
    touch "$LOG_FILE" "$ALERT_FILE"
}

# 루트키트 탐지
detect_rootkits() {
    log_step "루트키트 탐지 중..."
    
    local threats_found=()
    
    # chkrootkit 설치 확인
    if ! command -v chkrootkit &>/dev/null; then
        log_info "chkrootkit 설치 중..."
        pacman -S --needed chkrootkit 2>/dev/null || log_warning "chkrootkit 설치 실패"
    fi
    
    # rkhunter 설치 확인
    if ! command -v rkhunter &>/dev/null; then
        log_info "rkhunter 설치 중..."
        pacman -S --needed rkhunter 2>/dev/null || log_warning "rkhunter 설치 실패"
    fi
    
    # chkrootkit 실행
    if command -v chkrootkit &>/dev/null; then
        log_info "chkrootkit 스캔 실행 중..."
        local chkrootkit_output=$(chkrootkit -q 2>/dev/null || echo "")
        
        if [[ -n "$chkrootkit_output" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ INFECTED ]]; then
                    local threat=$(echo "$line" | cut -d: -f1)
                    threats_found+=("chkrootkit:$threat")
                    send_alert "CRITICAL" "루트키트 감지: $threat"
                fi
            done <<< "$chkrootkit_output"
        fi
    fi
    
    # rkhunter 실행
    if command -v rkhunter &>/dev/null; then
        log_info "rkhunter 스캔 실행 중..."
        local rkhunter_output=$(rkhunter --check --quiet --sk 2>/dev/null || echo "")
        
        if [[ -n "$rkhunter_output" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ Warning|Found ]]; then
                    local threat=$(echo "$line" | cut -d: -f2- | xargs)
                    threats_found+=("rkhunter:$threat")
                    send_alert "WARNING" "의심스러운 활동: $threat"
                fi
            done <<< "$rkhunter_output"
        fi
    fi
    
    # 수동 루트키트 검사
    local suspicious_files=(
        "/dev/.md5"
        "/dev/.initramfs"
        "/dev/.udev"
        "/dev/.systemd"
        "/dev/.kworker"
        "/usr/bin/.sshd"
        "/usr/bin/.bash"
        "/usr/bin/.sudo"
        "/lib/.ld.so"
        "/lib/.libdl.so"
    )
    
    for file in "${suspicious_files[@]}"; do
        if [[ -f "$file" ]]; then
            threats_found+=("suspicious_file:$file")
            send_alert "CRITICAL" "의심스러운 파일 발견: $file"
        fi
    done
    
    # 의심스러운 프로세스 검사
    local suspicious_processes=(
        "bash -i"
        "sh -i"
        "python -c"
        "perl -e"
        "nc -l"
        "ncat -l"
        "telnetd"
        "inetd"
        "xinetd"
    )
    
    for proc in "${suspicious_processes[@]}"; do
        if pgrep -f "$proc" &>/dev/null; then
            local pids=$(pgrep -f "$proc" | tr '\n' ',')
            threats_found+=("suspicious_process:$proc:$pids")
            send_alert "WARNING" "의심스러운 프로세스: $proc (PID: $pids)"
        fi
    done
    
    if [[ ${#threats_found[@]} -eq 0 ]]; then
        log_success "루트키트 탐지 완료 - 위협 없음"
    else
        log_warning "루트키트 탐지 완료 - ${#threats_found[@]}개 위협 발견"
    fi
    
    log_intrusion "루트키트 탐지 완료: ${#threats_found[@]}개 위협"
}

# 파일 무결성 검사
check_file_integrity() {
    log_step "파일 무결성 검사 중..."
    
    local integrity_issues=()
    local baseline_file="$INTRUSION_DIR/integrity.baseline"
    
    # 기준선 파일 생성 (첫 실행 시)
    if [[ ! -f "$baseline_file" ]]; then
        log_info "무결성 기준선 생성 중..."
        
        cat > "$baseline_file" << 'EOF'
# UnifiedArch OS 파일 무결성 기준선
# 형식: 파일:해시값:권한:소유자:그룹
EOF
        
        # 중요 시스템 파일 해시 계산
        local critical_files=(
            "/bin/bash"
            "/bin/sh"
            "/usr/bin/sudo"
            "/usr/bin/passwd"
            "/usr/bin/su"
            "/usr/bin/login"
            "/etc/passwd"
            "/etc/shadow"
            "/etc/group"
            "/etc/gshadow"
            "/etc/hosts"
            "/etc/hostname"
            "/etc/fstab"
            "/boot/grub/grub.cfg"
            "/boot/vmlinuz-linux"
        )
        
        for file in "${critical_files[@]}"; do
            if [[ -f "$file" ]]; then
                local hash=$(sha256sum "$file" | cut -d' ' -f1)
                local perms=$(stat -c "%a" "$file")
                local owner=$(stat -c "%U" "$file")
                local group=$(stat -c "%G" "$file")
                echo "$file:$hash:$perms:$owner:$group" >> "$baseline_file"
            fi
        done
        
        log_success "무결성 기준선 생성 완료"
        return 0
    fi
    
    # 파일 무결성 검사
    while IFS= read -r line; do
        if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
            continue
        fi
        
        local file=$(echo "$line" | cut -d: -f1)
        local expected_hash=$(echo "$line" | cut -d: -f2)
        local expected_perms=$(echo "$line" | cut -d: -f3)
        local expected_owner=$(echo "$line" | cut -d: -f4)
        local expected_group=$(echo "$line" | cut -d: -f5)
        
        if [[ -f "$file" ]]; then
            local current_hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)
            local current_perms=$(stat -c "%a" "$file" 2>/dev/null || echo "")
            local current_owner=$(stat -c "%U" "$file" 2>/dev/null || echo "")
            local current_group=$(stat -c "%G" "$file" 2>/dev/null || echo "")
            
            # 해시 검사
            if [[ "$current_hash" != "$expected_hash" ]]; then
                integrity_issues+=("hash_changed:$file")
                send_alert "CRITICAL" "파일 무결성 위반: $file (해시 변경)"
            fi
            
            # 권한 검사
            if [[ "$current_perms" != "$expected_perms" ]]; then
                integrity_issues+=("perms_changed:$file")
                send_alert "WARNING" "파일 권한 변경: $file ($expected_perms -> $current_perms)"
            fi
            
            # 소유자 검사
            if [[ "$current_owner" != "$expected_owner" ]]; then
                integrity_issues+=("owner_changed:$file")
                send_alert "WARNING" "파일 소유자 변경: $file ($expected_owner -> $current_owner)"
            fi
        else
            integrity_issues+=("file_missing:$file")
            send_alert "CRITICAL" "중요 파일 누락: $file"
        fi
    done < "$baseline_file"
    
    if [[ ${#integrity_issues[@]} -eq 0 ]]; then
        log_success "파일 무결성 검사 완료 - 문제 없음"
    else
        log_warning "파일 무결성 검사 완료 - ${#integrity_issues[@]}개 문제 발견"
    fi
    
    log_intrusion "파일 무결성 검사 완료: ${#integrity_issues[@]}개 문제"
}

# 네트워크 침해 감지
detect_network_intrusion() {
    log_step "네트워크 침해 감지 중..."
    
    local network_threats=()
    
    # 의심스러운 네트워크 연결 확인
    local suspicious_connections=$(netstat -tuln 2>/dev/null | grep -E "LISTEN|ESTABLISHED" | grep -v "127.0.0.1")
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local port=$(echo "$line" | awk '{print $4}' | cut -d: -f2)
            local address=$(echo "$line" | awk '{print $4}')
            
            # 의심스러운 포트 확인
            case "$port" in
                31337|12345|54321|6667|9999)
                    network_threats+=("suspicious_port:$port:$address")
                    send_alert "WARNING" "의심스러운 포트 활성: $port ($address)"
                    ;;
                4444|5555|7777)
                    network_threats+=("backdoor_port:$port:$address")
                    send_alert "CRITICAL" "백도어 포트 감지: $port ($address)"
                    ;;
            esac
        fi
    done <<< "$suspicious_connections"
    
    # 비정상적인 네트워크 트래픽 확인
    if command -v ss &>/dev/null; then
        local established_connections=$(ss -tuln state established 2>/dev/null | wc -l)
        
        if [[ $established_connections -gt 100 ]]; then
            network_threats+=("high_connections:$established_connections")
            send_alert "WARNING" "높은 네트워크 연결 수: $established_connections"
        fi
    fi
    
    # 의심스러운 프로세스 확인
    local suspicious_network_processes=(
        "nc -l"
        "ncat -l"
        "telnetd"
        "inetd"
        "xinetd"
        "python -m http.server"
        "php -S"
    )
    
    for proc in "${suspicious_network_processes[@]}"; do
        if pgrep -f "$proc" &>/dev/null; then
            network_threats+=("suspicious_network_process:$proc")
            send_alert "WARNING" "의심스러운 네트워크 프로세스: $proc"
        fi
    done
    
    # 방화벽 로그 분석
    if [[ -f "/var/log/ufw.log" ]]; then
        local blocked_attempts=$(grep -c "BLOCK" /var/log/ufw.log 2>/dev/null || echo "0")
        
        if [[ $blocked_attempts -gt 50 ]]; then
            network_threats+=("high_blocked_attempts:$blocked_attempts")
            send_alert "WARNING" "높은 방화벽 차단 시도: $blocked_attempts"
        fi
    fi
    
    if [[ ${#network_threats[@]} -eq 0 ]]; then
        log_success "네트워크 침해 감지 완료 - 위협 없음"
    else
        log_warning "네트워크 침해 감지 완료 - ${#network_threats[@]}개 위협 발견"
    fi
    
    log_intrusion "네트워크 침해 감지 완료: ${#network_threats[@]}개 위협"
}

# 시스템 로그 분석
analyze_system_logs() {
    log_step "시스템 로그 분석 중..."
    
    local log_threats=()
    
    # 인증 실패 로그 분석
    if [[ -f "/var/log/auth.log" ]]; then
        local auth_failures=$(grep -c "authentication failure" /var/log/auth.log 2>/dev/null || echo "0")
        
        if [[ $auth_failures -gt 10 ]]; then
            log_threats+=("high_auth_failures:$auth_failures")
            send_alert "WARNING" "높은 인증 실패 횟수: $auth_failures"
        fi
        
        # 의심스러운 로그인 시도
        local suspicious_ips=$(grep "authentication failure" /var/log/auth.log 2>/dev/null | grep -o "rhost=[^ ]*" | cut -d= -f2 | sort | uniq -c | sort -nr | head -5)
        
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local count=$(echo "$line" | awk '{print $1}')
                local ip=$(echo "$line" | awk '{print $2}')
                
                if [[ $count -gt 5 ]]; then
                    log_threats+=("suspicious_ip:$ip:$count")
                    send_alert "WARNING" "의심스러운 IP 로그인 시도: $ip ($count회)"
                fi
            fi
        done <<< "$suspicious_ips"
    fi
    
    # sudo 사용 로그 분석
    if [[ -f "/var/log/sudo.log" ]]; then
        local sudo_failures=$(grep -c "command not allowed" /var/log/sudo.log 2>/dev/null || echo "0")
        
        if [[ $sudo_failures -gt 5 ]]; then
            log_threats+=("sudo_failures:$sudo_failures")
            send_alert "WARNING" "높은 sudo 실패 횟수: $sudo_failures"
        fi
    fi
    
    # 시스템 오류 로그 분석
    local kernel_errors=$(journalctl -p err -n 100 --no-pager 2>/dev/null | grep -c "error\|fail\|panic" || echo "0")
    
    if [[ $kernel_errors -gt 20 ]]; then
        log_threats+=("high_kernel_errors:$kernel_errors")
        send_alert "WARNING" "높은 커널 오류 수: $kernel_errors"
    fi
    
    if [[ ${#log_threats[@]} -eq 0 ]]; then
        log_success "시스템 로그 분석 완료 - 위협 없음"
    else
        log_warning "시스템 로그 분석 완료 - ${#log_threats[@]}개 위협 발견"
    fi
    
    log_intrusion "시스템 로그 분석 완료: ${#log_threats[@]}개 위협"
}

# 자동 대응 조치
auto_response() {
    log_step "자동 대응 조치 실행 중..."
    
    local response_actions=()
    
    # 최근 알림 확인
    local recent_alerts=$(tail -10 "$ALERT_FILE" 2>/dev/null | grep -c "CRITICAL" || echo "0")
    
    if [[ $recent_alerts -gt 0 ]]; then
        # 침해 의심 시 자동 조치
        
        # 1. 의심스러운 IP 차단
        local suspicious_ips=$(grep "suspicious_ip" "$ALERT_FILE" 2>/dev/null | tail -5 | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+" | sort -u)
        
        for ip in $suspicious_ips; do
            if command -v ufw &>/dev/null; then
                ufw deny from "$ip" 2>/dev/null || log_warning "IP 차단 실패: $ip"
                response_actions+=("ip_blocked:$ip")
                log_intrusion "자동 IP 차단: $ip"
            fi
        done
        
        # 2. 의심스러운 프로세스 종료
        local suspicious_procs=$(pgrep -f "nc -l\|ncat -l\|telnetd" 2>/dev/null || echo "")
        
        for pid in $suspicious_procs; do
            kill -9 "$pid" 2>/dev/null || log_warning "프로세스 종료 실패: $pid"
            response_actions+=("process_killed:$pid")
            log_intrusion "자동 프로세스 종료: $pid"
        done
        
        # 3. 의심스러운 파일 격리
        local suspicious_files=(
            "/dev/.md5"
            "/dev/.initramfs"
            "/usr/bin/.sshd"
            "/lib/.ld.so"
        )
        
        for file in "${suspicious_files[@]}"; do
            if [[ -f "$file" ]]; then
                mv "$file" "$QUARANTINE_DIR/$(basename "$file")-$(date +%s)" 2>/dev/null || log_warning "파일 격리 실패: $file"
                response_actions+=("file_quarantined:$file")
                log_intrusion "자동 파일 격리: $file"
            fi
        done
        
        # 4. 보안 강화
        if command -v ufw &>/dev/null; then
            ufw --force enable 2>/dev/null || log_warning "방화벽 활성화 실패"
            response_actions+=("firewall_enabled")
        fi
        
        # 5. 관리자 알림
        send_alert "CRITICAL" "자동 대응 조치 실행됨: ${#response_actions[@]}개 조치"
    fi
    
    if [[ ${#response_actions[@]} -eq 0 ]]; then
        log_success "자동 대응 조치 완료 - 조치 필요 없음"
    else
        log_warning "자동 대응 조치 완료 - ${#response_actions[@]}개 조치 실행"
    fi
    
    log_intrusion "자동 대응 조치 완료: ${#response_actions[@]}개 조치"
}

# 보안 감사 실행
run_security_audit() {
    log_step "보안 감사 실행 중..."
    
    local audit_file="$AUDIT_DIR/security-audit-$(date +%Y%m%d-%H%M%S).log"
    
    cat > "$audit_file" << EOF
========================================
     UnifiedArch OS 보안 감사 보고서
 생성 시간: $(date '+%Y-%m-%d %H:%M:%S')
========================================

[시스템 정보]
호스트 이름: $(hostname)
커널 버전: $(uname -r)
아키텍처: $(uname -m)
가동 시간: $(uptime -s)

[사용자 정보]
총 사용자 수: $(cat /etc/passwd | wc -l)
활성 사용자 수: $(cat /etc/passwd | grep -c ":/bin/bash\|:/bin/zsh\|:/bin/fish")
root 사용자: $(cat /etc/passwd | grep -c "^root:")
UID 0 사용자: $(awk -F: '$3 == 0 {print $1}' /etc/passwd | wc -l)

[네트워크 정보]
활성 연결 수: $(netstat -tuln 2>/dev/null | grep -c "LISTEN\|ESTABLISHED")
열린 포트 수: $(netstat -tuln 2>/dev/null | grep "LISTEN" | wc -l)
방화벽 상태: $(systemctl is-active ufw 2>/dev/null || echo "비활성화")

[파일시스템 정보]
루트 파티션: $(findmnt -n -o SOURCE /)
파일시스템: $(findmnt -n -o FSTYPE /)
사용 공간: $(df -h / | tail -n1 | awk '{print $3}')
가용 공간: $(df -h / | tail -n1 | awk '{print $4}')

[서비스 정보]
활성 서비스 수: $(systemctl list-units --type=service --state=running --no-pager | wc -l)
실패 서비스 수: $(systemctl list-units --type=service --state=failed --no-pager | wc -l)
활성화된 서비스 수: $(systemctl list-units --type=service --state=enabled --no-pager | wc -l)

[보안 설정]
sudoers 파일: $(test -f /etc/sudoers && echo "존재" || echo "없음")
shadow 파일: $(test -f /etc/shadow && echo "존재" || echo "없음")
gshadow 파일: $(test -f /etc/gshadow && echo "존재" || echo "없음")
SELinux 상태: $(command -v getenforce &>/dev/null && getenforce || echo "설치 안됨")

[최근 보안 이벤트]
EOF
    
    # 최근 보안 이벤트 추가
    local recent_alerts=$(tail -20 "$ALERT_FILE" 2>/dev/null || echo "없음")
    echo "$recent_alerts" >> "$audit_file"
    
    cat >> "$audit_file" << EOF

========================================
EOF
    
    log_success "보안 감사 완료: $audit_file"
    log_intrusion "보안 감사 완료: $audit_file"
}

# 실시간 모니터링 시작
start_realtime_monitoring() {
    log_step "실시간 침해 감지 모니터링 시작 중..."
    
    # systemd 서비스 생성
    cat > "/etc/systemd/system/unifiedarch-intrusion-monitor.service" << 'EOF'
[Unit]
Description=UnifiedArch OS Intrusion Detection Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/unifiedarch-intrusion-monitor
Restart=always
RestartSec=300

[Install]
WantedBy=multi-user.target
EOF
    
    # 실시간 모니터링 스크립트
    cat > "/usr/local/bin/unifiedarch-intrusion-monitor" << 'EOF'
#!/bin/bash
# UnifiedArch OS 실시간 침해 감지 모니터

LOG_FILE="/var/log/unifiedarch-intrusion.log"
ALERT_FILE="/var/lib/unifiedarch/alerts.log"

log_intrusion() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MONITOR: \$1" >> "\$LOG_FILE"
}

# 실시간 로그 모니터링
monitor_logs() {
    journalctl -f --no-pager | while read -r line; do
        if [[ "\$line" =~ (authentication failure|sudo.*command not allowed|error|fail|panic) ]]; then
            log_intrusion "실시간 로그 이벤트: \$line"
        fi
    done
}

# 실시간 네트워크 모니터링
monitor_network() {
    ss -tuln state established 2>/dev/null | while read -r line; do
        if [[ "\$line" =~ (ESTABLISHED) ]]; then
            local connections=\$(ss -tuln state established 2>/dev/null | wc -l)
            if [[ \$connections -gt 100 ]]; then
                logger -t "unifiedarch-intrusion" "높은 네트워크 연결 수: \$connections"
            fi
        fi
    done
}

# 메인 모니터링 함수
main() {
    while true; do
        monitor_logs &
        monitor_network &
        sleep 60
    done
}

main "\$@"
EOF
    
    chmod +x "/usr/local/bin/unifiedarch-intrusion-monitor"
    
    # 서비스 활성화
    systemctl daemon-reload 2>/dev/null || log_warning "systemd 데몬 리로드 실패"
    systemctl enable unifiedarch-intrusion-monitor.service 2>/dev/null || log_warning "침해 감지 서비스 활성화 실패"
    systemctl start unifiedarch-intrusion-monitor.service 2>/dev/null || log_warning "침해 감지 서비스 시작 실패"
    
    log_success "실시간 침해 감지 모니터링 시작 완료"
    log_intrusion "실시간 침해 감지 모니터링 시작"
}

# 도움말
show_help() {
    echo "UnifiedArch OS Intrusion Detection System"
    echo ""
    echo "사용법: $0 [명령어]"
    echo ""
    echo "명령어:"
    echo "  scan-all          - 전체 침해 감지 스캔"
    echo "  detect-rootkits   - 루트키트 탐지"
    echo "  check-integrity   - 파일 무결성 검사"
    echo "  detect-network    - 네트워크 침해 감지"
    echo "  analyze-logs      - 시스템 로그 분석"
    echo "  auto-response     - 자동 대응 조치"
    echo "  audit             - 보안 감사 실행"
    echo "  monitor           - 실시간 모니터링 시작"
    echo "  help              - 이 도움말"
    echo ""
    echo "보안 기능:"
    echo "  - 루트키트 탐지 (chkrootkit, rkhunter)"
    echo "  - 파일 무결성 검사"
    echo "  - 네트워크 침해 감지"
    echo "  - 시스템 로그 분석"
    echo "  - 자동 대응 조치"
    echo "  - 실시간 모니터링"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    check_root
    create_directories
    
    case "$action" in
        scan-all)
            detect_rootkits
            check_file_integrity
            detect_network_intrusion
            analyze_system_logs
            auto_response
            ;;
        detect-rootkits)
            detect_rootkits
            ;;
        check-integrity)
            check_file_integrity
            ;;
        detect-network)
            detect_network_intrusion
            ;;
        analyze-logs)
            analyze_system_logs
            ;;
        auto-response)
            auto_response
            ;;
        audit)
            run_security_audit
            ;;
        monitor)
            start_realtime_monitoring
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
