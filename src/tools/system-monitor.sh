#!/bin/bash
# UnifiedArch OS 시스템 모니터 (사용자 공간 버전)
# 비상 응답 시스템의 사용자 공간 구현

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

# 시스템 상태 모니터링
monitor_system() {
    local memory_usage cpu_usage disk_usage temp_usage
    local alerts=0
    
    # 메모리 사용량 확인
    memory_usage=$(free | grep '^Mem:' | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $memory_usage -gt $MEMORY_THRESHOLD ]]; then
        log_alert "메모리 사용량 위험: ${memory_usage}% (임계값: ${MEMORY_THRESHOLD}%)"
        handle_memory_emergency
        ((alerts++))
    fi
    
    # CPU 사용량 확인
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    if [[ -n "$cpu_usage" && ${cpu_usage%.*} -gt $CPU_THRESHOLD ]]; then
        log_alert "CPU 사용량 위험: ${cpu_usage}% (임계값: ${CPU_THRESHOLD}%)"
        handle_cpu_emergency
        ((alerts++))
    fi
    
    # 디스크 사용량 확인
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt $DISK_THRESHOLD ]]; then
        log_alert "디스크 사용량 위험: ${disk_usage}% (임계값: ${DISK_THRESHOLD}%)"
        handle_disk_emergency
        ((alerts++))
    fi
    
    # 시스템 온도 확인 (가능한 경우)
    if command -v sensors >/dev/null 2>&1; then
        temp_usage=$(sensors | grep -i "core 0" | awk '{print $3}' | sed 's/+//' | sed 's/°C//' | head -1)
        if [[ -n "$temp_usage" && ${temp_usage%.*} -gt $TEMP_THRESHOLD ]]; then
            log_alert "시스템 온도 위험: ${temp_usage}°C (임계값: ${TEMP_THRESHOLD}°C)"
            handle_temp_emergency
            ((alerts++))
        fi
    fi
    
    # 네트워크 상태 확인
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_alert "네트워크 연결 없음"
        handle_network_emergency
        ((alerts++))
    fi
    
    # 보안 상태 확인
    check_security_status
    
    # 결과 보고
    echo ""
    echo "=== 시스템 상태 보고 ==="
    echo "메모리: ${memory_usage}%"
    echo "CPU: ${cpu_usage:-N/A}%"
    echo "디스크: ${disk_usage}%"
    echo "온도: ${temp_usage:-N/A}°C"
    echo "네트워크: $(ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "정상" || echo "연결 없음")"
    echo "경고 수: $alerts"
    
    return $alerts
}

# 메모리 비상 상황 처리
handle_memory_emergency() {
    log_info "메모리 확보 조치 실행 중..."
    
    # 캐시 정리
    sync
    echo 3 > /proc/sys/vm/drop_caches
    log_success "시스템 캐시 정리 완료"
    
    # 불필요한 프로세스 종료 (안전한 것만)
    local high_mem_processes=$(ps aux --sort=-%mem | head -10 | awk 'NR>1 && $3>50 {print $2}')
    for pid in $high_mem_processes; do
        if [[ -n "$pid" && "$pid" != "$$" ]]; then
            local process_name=$(ps -p "$pid" -o comm=)
            log_warning "고메모리 프로세스 종료: $process_name (PID: $pid)"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
}

# CPU 비상 상황 처리
handle_cpu_emergency() {
    log_info "CPU 부하 감소 조치 실행 중..."
    
    # 고부하 프로세스 확인
    local high_cpu_processes=$(ps aux --sort=-%cpu | head -10 | awk 'NR>1 && $3>80 {print $2}')
    for pid in $high_cpu_processes; do
        if [[ -n "$pid" && "$pid" != "$$" ]]; then
            local process_name=$(ps -p "$pid" -o comm=)
            log_warning "고부하 프로세스 우선순 낮춤: $process_name (PID: $pid)"
            renice +19 "$pid" 2>/dev/null || true
        fi
    done
}

# 디스크 비상 상황 처리
handle_disk_emergency() {
    log_info "디스크 공간 확보 조치 실행 중..."
    
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
}

# 온도 비상 상황 처리
handle_temp_emergency() {
    log_info "시스템 온도 감소 조치 실행 중..."
    
    # CPU 스로틀링
    if command -v cpupower >/dev/null 2>&1; then
        cpupower frequency-set -g powersave 2>/dev/null || true
    fi
    
    # 팬 속도 조절 (가능한 경우)
    if [[ -w /sys/class/thermal/thermal_zone0/mode ]]; then
        echo "enabled" > /sys/class/thermal/thermal_zone0/mode 2>/dev/null || true
    fi
}

# 네트워크 비상 상황 처리
handle_network_emergency() {
    log_info "네트워크 복구 조치 실행 중..."
    
    # 네트워크 재시작
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart NetworkManager 2>/dev/null || \
        systemctl restart networking 2>/dev/null || true
    fi
    
    # 네트워크 인터페이스 재시작
    ip link set down dev eth0 2>/dev/null || true
    ip link set up dev eth0 2>/dev/null || true
}

# 보안 상태 확인
check_security_status() {
    local security_issues=0
    
    # 로그인 실패 확인
    if command -v journalctl >/dev/null 2>&1; then
        local failed_logins=$(journalctl -u sshd | grep "Failed password" | wc -l)
        if [[ $failed_logins -gt 10 ]]; then
            log_warning "다수의 로그인 실패 감지: $failed_logins 회"
            ((security_issues++))
        fi
    fi
    
    # 포트 스캔 확인
    if command -v netstat >/dev/null 2>&1; then
        local suspicious_ports=$(netstat -tuln | grep -E ":22|:23|:3389" | wc -l)
        if [[ $suspicious_ports -gt 0 ]]; then
            log_warning "의심스러운 포트 열림: $suspicious_ports 개"
            ((security_issues++))
        fi
    fi
    
    # 방화벽 상태 확인
    if command -v ufw >/dev/null 2>&1; then
        if ! ufw status | grep -q "active"; then
            log_warning "방화벽 비활성화 상태"
            ((security_issues++))
        fi
    fi
    
    return $security_issues
}

# 실시간 모니터링 모드
start_realtime_monitoring() {
    local interval=${1:-30}
    
    log_info "실시간 모니터링 시작 (간격: ${interval}초)"
    
    while true; do
        clear
        echo "=== UnifiedArch OS 실시간 모니터링 ==="
        echo "시간: $(date)"
        echo "간격: ${interval}초"
        echo "종료: Ctrl+C"
        echo ""
        
        monitor_system
        
        echo ""
        echo "다음 체크까지 ${interval}초 대기..."
        sleep $interval
    done
}

# 시스템 정보 상세 보고
show_detailed_info() {
    echo "=== UnifiedArch OS 상세 시스템 정보 ==="
    echo ""
    
    echo "=== 기본 정보 ==="
    echo "호스트 이름: $(hostname)"
    echo "운영체제: $(uname -s -r)"
    echo "아키텍처: $(uname -m)"
    echo "업타임: $(uptime -p)"
    echo ""
    
    echo "=== 하드웨어 정보 ==="
    echo "CPU: $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)"
    echo "코어 수: $(nproc)"
    echo "메모리: $(free -h | grep '^Mem:' | awk '{print $2}')"
    echo "디스크: $(df -h / | tail -1 | awk '{print $2}')"
    echo ""
    
    echo "=== 네트워크 정보 ==="
    ip addr show | grep -E "^[0-9]+:" | awk '{print $2}' | cut -d: -f1
    echo ""
    
    echo "=== 프로세스 정보 ==="
    echo "총 프로세스: $(ps aux | wc -l)"
    echo "실행 중: $(ps aux | awk '$8 ~ /R|S/ {print}' | wc -l)"
    echo "최대 메모리 사용: $(ps aux --sort=-%mem | head -2 | tail -1 | awk '{print $4, $11}')"
    echo ""
    
    echo "=== 서비스 상태 ==="
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-units --type=service --state=running | head -10
    fi
    echo ""
    
    echo "=== 보안 정보 ==="
    echo "방화벽: $(command -v ufw >/dev/null 2>&1 && ufw status | head -1 || echo "UFW 없음")"
    echo "SELinux: $(command -v sestatus >/dev/null 2>&1 && sestatus | head -1 || echo "SELinux 없음")"
    echo ""
    
    echo "=== 로그인 정보 ==="
    echo "현재 사용자: $(whoami)"
    echo "로그인한 사용자: $(who | wc -l)"
    echo "마지막 로그인: $(last -n 1 | awk '{print $1, $3, $4, $5}')"
}

# 성능 벤치마크
run_benchmark() {
    echo "=== UnifiedArch OS 성능 벤치마크 ==="
    echo ""
    
    # CPU 벤치마크
    echo "CPU 벤치마크 (10초)..."
    local cpu_start=$(date +%s.%N)
    for i in {1..1000000}; do
        echo $i > /dev/null
    done
    local cpu_end=$(date +%s.%N)
    local cpu_time=$(echo "$cpu_end - $cpu_start" | bc -l)
    echo "CPU 처리 시간: ${cpu_time}초"
    
    # 메모리 벤치마크
    echo "메모리 벤치마크..."
    local mem_start=$(date +%s.%N)
    dd if=/dev/zero of=/dev/null bs=1M count=100 2>/dev/null
    local mem_end=$(date +%s.%N)
    local mem_time=$(echo "$mem_end - $mem_start" | bc -l)
    echo "메모리 처리 시간: ${mem_time}초"
    
    # 디스크 I/O 벤치마크
    echo "디스크 I/O 벤치마크..."
    local disk_start=$(date +%s.%N)
    dd if=/dev/zero of=/tmp/benchmark bs=1M count=50 2>/dev/null
    rm -f /tmp/benchmark
    local disk_end=$(date +%s.%N)
    local disk_time=$(echo "$disk_end - $disk_start" | bc -l)
    echo "디스크 쓰기 시간: ${disk_time}초"
    
    echo ""
    echo "벤치마크 완료"
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 시스템 모니터"
    echo ""
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  monitor              - 시스템 상태 모니터링"
    echo "  realtime [interval] - 실시간 모니터링 (기본 30초)"
    echo "  info                 - 상세 시스템 정보"
    echo "  benchmark            - 성능 벤치마크"
    echo "  help                 - 이 도움말 표시"
    echo ""
    echo "예시:"
    echo "  $0 monitor           - 한 번 모니터링"
    echo "  $0 realtime 10        - 10초 간격 실시간 모니터링"
    echo "  $0 info              - 상세 정보 보기"
    echo "  $0 benchmark         - 성능 테스트"
}

# 메인 함수
main() {
    local command="${1:-monitor}"
    
    case "$command" in
        "monitor")
            monitor_system
            ;;
        "realtime")
            start_realtime_monitoring "${2:-30}"
            ;;
        "info")
            show_detailed_info
            ;;
        "benchmark")
            run_benchmark
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
