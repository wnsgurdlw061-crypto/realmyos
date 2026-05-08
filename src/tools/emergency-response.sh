#!/bin/bash
# UnifiedArch OS Emergency Response System (Userspace Version)
# 실제 동작하는 비상 응답 시스템

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

log_alert() {
    echo -e "${PURPLE}[ALERT]${NC} $1"
}

# 임계값 설정
MEMORY_THRESHOLD=90
CPU_THRESHOLD=95
DISK_THRESHOLD=95
TEMP_THRESHOLD=70

# 비상 로그
EMERGENCY_LOG="$HOME/.unifiedarch_emergency.log"

# 비상 상황 처리
handle_emergency() {
    local emergency_type="$1"
    local severity="$2"
    local description="$3"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 로그 기록
    echo "[$timestamp] EMERGENCY: $emergency_type (Severity: $severity) - $description" >> "$EMERGENCY_LOG"
    
    log_alert "비상 상황 감지: $description"
    
    case "$emergency_type" in
        "MEMORY_CRITICAL")
            handle_memory_emergency
            ;;
        "CPU_OVERLOAD")
            handle_cpu_emergency
            ;;
        "DISK_FULL")
            handle_disk_emergency
            ;;
        "TEMP_HIGH")
            handle_temp_emergency
            ;;
        "NETWORK_FAILURE")
            handle_network_emergency
            ;;
        "SECURITY_BREACH")
            handle_security_emergency
            ;;
        *)
            log_warning "알 수 없는 비상 타입: $emergency_type"
            ;;
    esac
}

# 메모리 비상 상황 처리
handle_memory_emergency() {
    log_info "메모리 확보 조치 실행 중..."
    
    # 캐시 정리
    if [[ $EUID -eq 0 ]]; then
        sync
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        log_success "시스템 캐시 정리 완료"
    fi
    
    # 고메모리 프로세스 확인
    local high_mem=$(ps aux --sort=-%mem | head -10 | awk 'NR>1 && $3>50 {print $2}')
    for pid in $high_mem; do
        if [[ -n "$pid" && "$pid" != "$$" ]]; then
            local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            log_warning "고메모리 프로세스: $process_name (PID: $pid, MEM: $(ps -p "$pid" -o %mem= 2>/dev/null || echo "N/A")%)"
        fi
    done
}

# CPU 비상 상황 처리
handle_cpu_emergency() {
    log_info "CPU 부하 감소 조치 실행 중..."
    
    # 고부하 프로세스 확인
    local high_cpu=$(ps aux --sort=-%cpu | head -10 | awk 'NR>1 && $3>80 {print $2}')
    for pid in $high_cpu; do
        if [[ -n "$pid" && "$pid" != "$$" ]]; then
            local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            log_warning "고부하 프로세스: $process_name (PID: $pid, CPU: $(ps -p "$pid" -o %cpu= 2>/dev/null || echo "N/A")%)"
            
            # 우선순위 낮춤 (루트 권한 있을 경우)
            if [[ $EUID -eq 0 ]]; then
                renice +19 "$pid" 2>/dev/null || true
            fi
        fi
    done
}

# 디스크 비상 상황 처리
handle_disk_emergency() {
    log_info "디스크 공간 확보 조치 실행 중..."
    
    if [[ $EUID -eq 0 ]]; then
        # 임시 파일 정리
        find /tmp -type f -atime +7 -delete 2>/dev/null || true
        find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
        
        # 패키지 캐시 정리
        if command -v apt >/dev/null 2>&1; then
            apt clean 2>/dev/null || true
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Scc --noconfirm 2>/dev/null || true
        fi
        
        # 로그 파일 정리
        find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null || true
        find /var/log -name "*.log.*" -delete 2>/dev/null || true
        
        log_success "디스크 공간 정리 완료"
    else
        log_warning "디스크 정리에는 루트 권한이 필요합니다"
    fi
}

# 온도 비상 상황 처리
handle_temp_emergency() {
    log_info "시스템 온도 감소 조치 실행 중..."
    
    if [[ $EUID -eq 0 ]]; then
        # CPU 스로틀링
        if command -v cpupower >/dev/null 2>&1; then
            cpupower frequency-set -g powersave 2>/dev/null || true
            log_success "CPU 파워세이프 모드 활성화"
        fi
        
        # 팬 속도 조절
        if [[ -w /sys/class/thermal/thermal_zone0/mode ]]; then
            echo "enabled" > /sys/class/thermal/thermal_zone0/mode 2>/dev/null || true
        fi
    fi
}

# 네트워크 비상 상황 처리
handle_network_emergency() {
    log_info "네트워크 복구 조치 실행 중..."
    
    if [[ $EUID -eq 0 ]]; then
        # 네트워크 재시작
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart NetworkManager 2>/dev/null || \
            systemctl restart networking 2>/dev/null || true
            log_success "네트워크 서비스 재시작"
        fi
        
        # 네트워크 인터페이스 재시작
        ip link set down dev eth0 2>/dev/null || true
        ip link set up dev eth0 2>/dev/null || true
    fi
}

# 보안 비상 상황 처리
handle_security_emergency() {
    log_info "보안 위협 대응 조치 실행 중..."
    
    if [[ $EUID -eq 0 ]]; then
        # 방화벽 활성화
        if command -v ufw >/dev/null 2>&1; then
            ufw --force enable 2>/dev/null || true
            log_success "방화벽 강제 활성화"
        fi
        
        # 의심스러운 로그인 세션 확인
        local suspicious_logins=$(last | grep -E "still logged in|crash|reboot" | wc -l)
        if [[ $suspicious_logins -gt 0 ]]; then
            log_warning "의심스러운 로그인 세션: $suspicious_logins 개"
        fi
    fi
}

# 시스템 상태 모니터링
monitor_system() {
    local alerts=0
    
    # 메모리 사용량 확인
    local memory_usage=$(free | grep '^Mem:' | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $memory_usage -gt $MEMORY_THRESHOLD ]]; then
        handle_emergency "MEMORY_CRITICAL" "8" "메모리 사용량 ${memory_usage}% (임계값: ${MEMORY_THRESHOLD}%)"
        ((alerts++))
    fi
    
    # CPU 사용량 확인
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "0")
    if [[ -n "$cpu_usage" && ${cpu_usage%.*} -gt $CPU_THRESHOLD ]]; then
        handle_emergency "CPU_OVERLOAD" "7" "CPU 사용량 ${cpu_usage}% (임계값: ${CPU_THRESHOLD}%)"
        ((alerts++))
    fi
    
    # 디스크 사용량 확인
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt $DISK_THRESHOLD ]]; then
        handle_emergency "DISK_FULL" "9" "디스크 사용량 ${disk_usage}% (임계값: ${DISK_THRESHOLD}%)"
        ((alerts++))
    fi
    
    # 시스템 온도 확인
    if command -v sensors >/dev/null 2>&1; then
        local temp_usage=$(sensors | grep -i "core 0" | awk '{print $3}' | sed 's/+//' | sed 's/°C//' | head -1)
        if [[ -n "$temp_usage" && ${temp_usage%.*} -gt $TEMP_THRESHOLD ]]; then
            handle_emergency "TEMP_HIGH" "6" "시스템 온도 ${temp_usage}°C (임계값: ${TEMP_THRESHOLD}°C)"
            ((alerts++))
        fi
    fi
    
    # 네트워크 상태 확인
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        handle_emergency "NETWORK_FAILURE" "8" "네트워크 연결 없음"
        ((alerts++))
    fi
    
    # 보안 상태 확인
    check_security_threats
    local security_status=$?
    if [[ $security_status -gt 0 ]]; then
        handle_emergency "SECURITY_BREACH" "10" "보안 위협 감지됨"
        ((alerts++))
    fi
    
    return $alerts
}

# 보안 위협 확인
check_security_threats() {
    local threats=0
    
    # 로그인 실패 확인
    if command -v journalctl >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        local failed_logins=$(journalctl -u sshd --since "1 hour ago" | grep "Failed password" | wc -l)
        if [[ $failed_logins -gt 10 ]]; then
            log_warning "다수의 로그인 실패: $failed_logins 회 (1시간 내)"
            ((threats++))
        fi
    fi
    
    # 의심스러운 포트 확인
    if command -v netstat >/dev/null 2>&1; then
        local suspicious_ports=$(netstat -tuln 2>/dev/null | grep -E ":22|:23|:3389|:5900" | wc -l)
        if [[ $suspicious_ports -gt 2 ]]; then
            log_warning "의심스러운 포트 열림: $suspicious_ports 개"
            ((threats++))
        fi
    fi
    
    return $threats
}

# 비상 로그 보기
show_emergency_log() {
    if [[ -f "$EMERGENCY_LOG" ]]; then
        echo "=== UnifiedArch OS Emergency Log ==="
        echo "로그 파일: $EMERGENCY_LOG"
        echo "마지막 20개 항목:"
        tail -20 "$EMERGENCY_LOG"
        echo ""
        echo "총 비상 이벤트: $(wc -l < "$EMERGENCY_LOG")개"
    else
        log_info "비상 로그 파일 없음: $EMERGENCY_LOG"
    fi
}

# 실시간 모니터링
start_realtime_monitoring() {
    local interval=${1:-30}
    
    log_info "실시간 비상 모니터링 시작 (간격: ${interval}초)"
    log_info "종료: Ctrl+C"
    
    while true; do
        clear
        echo "=== UnifiedArch OS Emergency Response System ==="
        echo "버전: $VERSION"
        echo "시간: $(date)"
        echo "간격: ${interval}초"
        echo ""
        
        monitor_system
        local alert_count=$?
        
        echo ""
        if [[ $alert_count -eq 0 ]]; then
            log_success "시스템 정상 - 비상 상황 없음"
        else
            log_alert "$alert_count 개의 비상 상황 감지됨"
        fi
        
        echo ""
        echo "다음 체크까지 ${interval}초 대기..."
        sleep $interval
    done
}

# 시스템 테스트
run_emergency_test() {
    log_info "비상 응답 시스템 테스트 시작"
    
    # 메모리 테스트
    handle_emergency "MEMORY_CRITICAL" "5" "테스트: 메모리 비상 상황"
    sleep 1
    
    # CPU 테스트
    handle_emergency "CPU_OVERLOAD" "5" "테스트: CPU 비상 상황"
    sleep 1
    
    # 디스크 테스트
    handle_emergency "DISK_FULL" "5" "테스트: 디스크 비상 상황"
    sleep 1
    
    # 네트워크 테스트
    handle_emergency "NETWORK_FAILURE" "5" "테스트: 네트워크 비상 상황"
    sleep 1
    
    # 보안 테스트
    handle_emergency "SECURITY_BREACH" "5" "테스트: 보안 비상 상황"
    
    log_success "비상 응답 시스템 테스트 완료"
    show_emergency_log
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS Emergency Response System"
    echo ""
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  monitor              - 시스템 상태 모니터링"
    echo "  realtime [interval]  - 실시간 모니터링 (기본 30초)"
    echo "  test                 - 비상 응답 시스템 테스트"
    echo "  log                  - 비상 로그 보기"
    echo "  help                 - 이 도움말 표시"
    echo ""
    echo "예시:"
    echo "  $0 monitor           - 한 번 모니터링"
    echo "  $0 realtime 10       - 10초 간격 실시간 모니터링"
    echo "  $0 test              - 시스템 테스트"
    echo "  $0 log               - 비상 로그 확인"
    echo ""
    echo "임계값:"
    echo "  메모리: ${MEMORY_THRESHOLD}%"
    echo "  CPU: ${CPU_THRESHOLD}%"
    echo "  디스크: ${DISK_THRESHOLD}%"
    echo "  온도: ${TEMP_THRESHOLD}°C"
}

# 메인 함수
main() {
    local command="${1:-monitor}"
    
    # 로그 디렉토리 생성
    mkdir -p "$(dirname "$EMERGENCY_LOG")"
    
    case "$command" in
        "monitor")
            monitor_system
            ;;
        "realtime")
            start_realtime_monitoring "${2:-30}"
            ;;
        "test")
            run_emergency_test
            ;;
        "log")
            show_emergency_log
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
