#!/bin/bash
# UnifiedArch OS 시스템 서비스
# 완벽한 시스템 서비스 및 데몬 관리

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
SERVICE_NAME="unifiedarch"
PID_FILE="/var/run/unifiedarch.pid"
LOG_FILE="/var/log/unifiedarch.log"
CONFIG_FILE="/etc/unifiedarch/service.conf"

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
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $1" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >> "$LOG_FILE"
}

# 서비스 상태 확인
check_service_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0  # 실행 중
        else
            rm -f "$PID_FILE"  # 죽은 프로세스 정리
            return 1  # 실행 중 아님
        fi
    else
        return 1  # 실행 중 아님
    fi
}

# 서비스 시작
start_service() {
    if check_service_status; then
        log_warning "UnifiedArch 서비스가 이미 실행 중입니다"
        return 0
    fi
    
    log_info "UnifiedArch 서비스 시작 중..."
    
    # 로그 디렉토리 생성
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 설정 파일 생성
    create_service_config
    
    # 백그라운드에서 서비스 실행
    nohup bash -c "
        while true; do
            # 시스템 모니터링
            monitor_system_health
            
            # 보안 모니터링
            monitor_security_status
            
            # 네트워크 모니터링
            monitor_network_status
            
            # 60초 대기
            sleep 60
        done
    " >/dev/null 2>&1 &
    
    # PID 저장
    echo $! > "$PID_FILE"
    
    log_success "UnifiedArch 서비스 시작 완료 (PID: $(cat "$PID_FILE"))"
}

# 서비스 중지
stop_service() {
    if ! check_service_status; then
        log_warning "UnifiedArch 서비스가 실행 중이 아닙니다"
        return 0
    fi
    
    local pid=$(cat "$PID_FILE")
    log_info "UnifiedArch 서비스 중지 중... (PID: $pid)"
    
    # 정상 종료 시도
    kill -TERM "$pid" 2>/dev/null || true
    
    # 5초 대기
    sleep 5
    
    # 강제 종료 필요한 경우
    if kill -0 "$pid" 2>/dev/null; then
        log_warning "서비스 강제 종료 중..."
        kill -KILL "$pid" 2>/dev/null || true
    fi
    
    # PID 파일 제거
    rm -f "$PID_FILE"
    
    log_success "UnifiedArch 서비스 중지 완료"
}

# 서비스 재시작
restart_service() {
    log_info "UnifiedArch 서비스 재시작 중..."
    stop_service
    sleep 2
    start_service
}

# 서비스 상태 보기
show_service_status() {
    echo "=== UnifiedArch OS 서비스 상태 ==="
    echo ""
    
    if check_service_status; then
        local pid=$(cat "$PID_FILE")
        echo -e "상태: ${GREEN}실행 중${NC}"
        echo "PID: $pid"
        echo "시작 시간: $(ps -p "$pid" -o lstart= 2>/dev/null || echo "알 수 없음")"
        echo "메모리 사용: $(ps -p "$pid" -o %mem= 2>/dev/null || echo "알 수 없음")%"
        echo "CPU 사용: $(ps -p "$pid" -o %cpu= 2>/dev/null || echo "알 수 없음")%"
    else
        echo -e "상태: ${RED}중지됨${NC}"
    fi
    
    echo ""
    echo "설정 파일: $CONFIG_FILE"
    echo "로그 파일: $LOG_FILE"
    echo "PID 파일: $PID_FILE"
    
    # 최근 로그 보기
    if [[ -f "$LOG_FILE" ]]; then
        echo ""
        echo "=== 최근 로그 (10개) ==="
        tail -10 "$LOG_FILE"
    fi
}

# 서비스 설정 생성
create_service_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        
        cat > "$CONFIG_FILE" << 'EOF'
# UnifiedArch OS 서비스 설정

# 모니터링 간격 (초)
MONITOR_INTERVAL=60

# 로그 레벨 (DEBUG, INFO, WARNING, ERROR)
LOG_LEVEL=INFO

# 보안 모니터링 활성화
SECURITY_MONITORING=true

# 네트워크 모니터링 활성화
NETWORK_MONITORING=true

# 성능 모니터링 활성화
PERFORMANCE_MONITORING=true

# 알림 설정
ENABLE_EMAIL_ALERTS=false
EMAIL_RECIPIENT=""
SMTP_SERVER=""

# 자동 응답 설정
AUTO_RESPONSE_ENABLED=true
AUTO_RESPONSE_LEVEL=medium

# 백업 설정
AUTO_BACKUP_ENABLED=false
BACKUP_INTERVAL=daily
BACKUP_LOCATION="/var/backups/unifiedarch"

# 시스템 임계값
MEMORY_THRESHOLD=90
CPU_THRESHOLD=95
DISK_THRESHOLD=95
TEMP_THRESHOLD=70
EOF
        
        log_info "서비스 설정 파일 생성됨: $CONFIG_FILE"
    fi
}

# 시스템 건강 모니터링
monitor_system_health() {
    # 메모리 사용량 확인
    local memory_usage=$(free | grep '^Mem:' | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $memory_usage -gt 90 ]]; then
        log_warning "메모리 사용량 위험: ${memory_usage}%"
        trigger_auto_response "memory_high" "$memory_usage"
    fi
    
    # CPU 사용량 확인
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "0")
    if [[ -n "$cpu_usage" && ${cpu_usage%.*} -gt 95 ]]; then
        log_warning "CPU 사용량 위험: ${cpu_usage}%"
        trigger_auto_response "cpu_high" "$cpu_usage"
    fi
    
    # 디스크 사용량 확인
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 95 ]]; then
        log_warning "디스크 사용량 위험: ${disk_usage}%"
        trigger_auto_response "disk_high" "$disk_usage"
    fi
    
    # 시스템 온도 확인
    if command -v sensors >/dev/null 2>&1; then
        local temp_usage=$(sensors | grep -i "core 0" | awk '{print $3}' | sed 's/+//' | sed 's/°C//' | head -1)
        if [[ -n "$temp_usage" && ${temp_usage%.*} -gt 70 ]]; then
            log_warning "시스템 온도 위험: ${temp_usage}°C"
            trigger_auto_response "temp_high" "$temp_usage"
        fi
    fi
}

# 보안 상태 모니터링
monitor_security_status() {
    # 로그인 실패 확인
    if command -v journalctl >/dev/null 2>&1; then
        local failed_logins=$(journalctl -u sshd --since "1 hour ago" | grep "Failed password" | wc -l)
        if [[ $failed_logins -gt 10 ]]; then
            log_warning "다수의 로그인 실패: $failed_logins 회 (1시간 내)"
            trigger_auto_response "security_breach" "$failed_logins"
        fi
    fi
    
    # 의심스러운 프로세스 확인
    local suspicious_processes=$(ps aux | grep -E "(nc|netcat|nmap|wireshark|tcpdump)" | grep -v grep | wc -l)
    if [[ $suspicious_processes -gt 0 ]]; then
        log_warning "의심스러운 프로세스 감지: $suspicious_processes 개"
        trigger_auto_response "suspicious_process" "$suspicious_processes"
    fi
    
    # 방화벽 상태 확인
    if command -v ufw >/dev/null 2>&1; then
        if ! ufw status | grep -q "active"; then
            log_warning "방화벽 비활성화 상태"
            trigger_auto_response "firewall_disabled" "0"
        fi
    fi
}

# 네트워크 상태 모니터링
monitor_network_status() {
    # 네트워크 연결 확인
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_warning "네트워크 연결 없음"
        trigger_auto_response "network_down" "0"
    fi
    
    # 네트워크 인터페이스 상태 확인
    local network_interfaces=$(ip link show | grep -E "state UP" | wc -l)
    if [[ $network_interfaces -eq 0 ]]; then
        log_warning "활성 네트워크 인터페이스 없음"
        trigger_auto_response "no_interfaces" "$network_interfaces"
    fi
    
    # 포트 스캔 확인
    if command -v netstat >/dev/null 2>&1; then
        local open_ports=$(netstat -tuln | grep -c "LISTEN")
        if [[ $open_ports -gt 50 ]]; then
            log_warning "과도한 열린 포트: $open_ports 개"
            trigger_auto_response "too_many_ports" "$open_ports"
        fi
    fi
}

# 자동 응답 트리거
trigger_auto_response() {
    local event_type="$1"
    local event_value="$2"
    
    # 설정 파일에서 자동 응답 설정 읽기
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
    
    # 자동 응답이 비활성화된 경우
    if [[ "${AUTO_RESPONSE_ENABLED:-false}" != "true" ]]; then
        return 0
    fi
    
    case "$event_type" in
        "memory_high")
            if [[ "${AUTO_RESPONSE_LEVEL:-medium}" == "high" ]]; then
                log_info "자동 메모리 정리 실행"
                sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
            fi
            ;;
        "cpu_high")
            if [[ "${AUTO_RESPONSE_LEVEL:-medium}" != "low" ]]; then
                log_info "고부하 프로세스 우선순 낮춤"
                ps aux --sort=-%cpu | head -5 | awk 'NR>1 && $3>80 {print $2}' | xargs -r renice +19 2>/dev/null || true
            fi
            ;;
        "disk_high")
            if [[ "${AUTO_RESPONSE_LEVEL:-medium}" == "high" ]]; then
                log_info "자동 디스크 정리 실행"
                find /tmp -type f -atime +7 -delete 2>/dev/null || true
                find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
            fi
            ;;
        "security_breach")
            log_info "보안 위협 자동 대응"
            if command -v ufw >/dev/null 2>&1; then
                ufw --force enable 2>/dev/null || true
            fi
            ;;
        "network_down")
            if [[ "${AUTO_RESPONSE_LEVEL:-medium}" != "low" ]]; then
                log_info "네트워크 서비스 재시작"
                systemctl restart NetworkManager 2>/dev/null || true
            fi
            ;;
        *)
            log_info "이벤트 감지: $event_type (값: $event_value)"
            ;;
    esac
}

# 서비스 로그 보기
show_service_logs() {
    local lines="${1:-50}"
    
    echo "=== UnifiedArch OS 서비스 로그 ==="
    echo "최근 $lines개 항목:"
    echo ""
    
    if [[ -f "$LOG_FILE" ]]; then
        tail -n "$lines" "$LOG_FILE"
    else
        log_info "로그 파일 없음: $LOG_FILE"
    fi
}

# 서비스 로그 정리
clean_service_logs() {
    log_info "서비스 로그 정리 중..."
    
    if [[ -f "$LOG_FILE" ]]; then
        # 최근 1000줄만 남기고 정리
        tail -n 1000 "$LOG_FILE" > "$LOG_FILE.tmp"
        mv "$LOG_FILE.tmp" "$LOG_FILE"
        
        local original_size=$(du -h "$LOG_FILE" | cut -f1)
        log_success "로그 정리 완료 (크기: $original_size)"
    fi
}

# 서비스 설치
install_service() {
    log_info "UnifiedArch OS 서비스 설치 중..."
    
    # systemd 서비스 파일 생성
    if command -v systemctl >/dev/null 2>&1; then
        cat > "/etc/systemd/system/unifiedarch.service" << EOF
[Unit]
Description=UnifiedArch OS Service
After=network.target
Wants=network.target

[Service]
Type=forking
PIDFile=$PID_FILE
ExecStart=/opt/unifiedarch/src/services/unifiedarch-service.sh start
ExecStop=/opt/unifiedarch/src/services/unifiedarch-service.sh stop
ExecReload=/opt/unifiedarch/src/services/unifiedarch-service.sh restart
Restart=always
RestartSec=10
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
        
        # systemd 리로드
        systemctl daemon-reload
        
        # 서비스 활성화
        systemctl enable unifiedarch 2>/dev/null || true
        
        log_success "systemd 서비스 설치 완료"
    else
        log_warning "systemd를 찾을 수 없습니다. 수동 시작이 필요합니다."
    fi
}

# 서비스 제거
uninstall_service() {
    log_info "UnifiedArch OS 서비스 제거 중..."
    
    # 서비스 중지
    stop_service
    
    # systemd 서비스 제거
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable unifiedarch 2>/dev/null || true
        rm -f "/etc/systemd/system/unifiedarch.service"
        systemctl daemon-reload
        log_success "systemd 서비스 제거 완료"
    fi
    
    # 설정 및 로그 파일 제거
    read -p "설정 파일과 로그도 제거하시겠습니까? (y/N): " remove_data
    if [[ $remove_data =~ ^[Yy]$ ]]; then
        rm -f "$CONFIG_FILE" "$LOG_FILE" "$PID_FILE"
        log_success "설정 및 로그 파일 제거 완료"
    fi
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 시스템 서비스"
    echo ""
    echo "사용법: $0 [명령]"
    echo ""
    echo "명령:"
    echo "  start          - 서비스 시작"
    echo "  stop           - 서비스 중지"
    echo "  restart        - 서비스 재시작"
    echo "  status         - 서비스 상태 보기"
    echo "  logs [lines]   - 서비스 로그 보기"
    echo "  clean          - 로그 정리"
    echo "  install        - 시스템 서비스 설치"
    echo "  uninstall      - 시스템 서비스 제거"
    echo "  help           - 이 도움말 표시"
    echo ""
    echo "예시:"
    echo "  $0 start           - 서비스 시작"
    echo "  $0 status          - 상태 확인"
    echo "  $0 logs 100        - 최근 100개 로그 보기"
}

# 메인 함수
main() {
    local command="${1:-help}"
    
    case "$command" in
        "start")
            start_service
            ;;
        "stop")
            stop_service
            ;;
        "restart")
            restart_service
            ;;
        "status")
            show_service_status
            ;;
        "logs")
            show_service_logs "${2:-50}"
            ;;
        "clean")
            clean_service_logs
            ;;
        "install")
            install_service
            ;;
        "uninstall")
            uninstall_service
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
