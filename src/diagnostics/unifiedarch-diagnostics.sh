#!/bin/bash
#
# UnifiedArch OS System Diagnostics Tool
# 시스템 진단 및 로그 분석 도구
#
# 기능:
# - 부팅 로그, 커널 로그, 네트워크 상태 분석
# - 서비스 상태, 하드웨어 정보 진단
# - 통합 진단 대시보드
#

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
DIAGNOSTICS_DIR="/var/lib/unifiedarch/diagnostics"
REPORT_DIR="/var/lib/unifiedarch/reports"
LOG_FILE="/var/log/unifiedarch-diagnostics.log"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${PURPLE}[STEP]${NC} $1"; }

# 로그 함수
log_diag() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DIAG: $1" >> "$LOG_FILE"
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
    mkdir -p "$DIAGNOSTICS_DIR" "$REPORT_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# 시스템 정보 수집
collect_system_info() {
    log_step "시스템 정보 수집 중..."
    
    local system_info=()
    
    # 기본 정보
    system_info[hostname]="$(hostname)"
    system_info[kernel]="$(uname -r)"
    system_info[arch]="$(uname -m)"
    system_info[uptime]="$(uptime -s)"
    system_info[load]="$(uptime | grep -o 'load average:.*' | awk '{print $3}')"
    
    # 메모리 정보
    local mem_info=$(free -h)
    system_info[total_memory]=$(echo "$mem_info" | grep '^Mem:' | awk '{print $2}')
    system_info[used_memory]=$(echo "$mem_info" | grep '^Mem:' | awk '{print $3}')
    system_info[free_memory]=$(echo "$mem_info" | grep '^Mem:' | awk '{print $7}')
    system_info[swap_total]=$(echo "$mem_info" | grep '^Swap:' | awk '{print $2}')
    system_info[swap_used]=$(echo "$mem_info" | grep '^Swap:' | awk '{print $3}')
    
    # CPU 정보
    system_info[cpu_model]=$(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)
    system_info[cpu_cores]=$(grep -c '^processor' /proc/cpuinfo | wc -l)
    system_info[cpu_threads]=$(grep 'siblings' /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)
    
    # 디스크 정보
    local disk_info=$(df -h /)
    system_info[root_device]=$(findmnt -n -o SOURCE /)
    system_info[root_fs]=$(findmnt -n -o FSTYPE /)
    system_info[root_size]=$(echo "$disk_info" | tail -n1 | awk '{print $2}')
    system_info[root_used]=$(echo "$disk_info" | tail -n1 | awk '{print $3}')
    system_info[root_available]=$(echo "$disk_info" | tail -n1 | awk '{print $4}')
    
    echo "${system_info[@]}"
    log_diag "시스템 정보 수집 완료"
}

# 부팅 로그 분석
analyze_boot_logs() {
    log_step "부팅 로그 분석 중..."
    
    local boot_issues=()
    local boot_time=""
    local boot_status="normal"
    
    # systemd journal 부팅 로그
    local journal_output=$(journalctl -b 0 -p err -n 10 --no-pager 2>/dev/null)
    if [[ -n "$journal_output" ]]; then
        boot_issues+=("systemd: $(echo "$journal_output" | wc -l)개 오류")
        boot_status="errors"
    fi
    
    # 커널 로그 분석
    local kernel_errors=$(dmesg | grep -i 'error\|fail\|panic\|oops' | head -5 2>/dev/null)
    if [[ -n "$kernel_errors" ]]; then
        boot_issues+=("kernel: $(echo "$kernel_errors" | wc -l)개 오류")
        boot_status="errors"
    fi
    
    # 부팅 시간 계산
    boot_time=$(systemd-analyze | grep 'Startup finished' | cut -d= -f2 | tr -d ' ')
    if [[ -z "$boot_time" ]]; then
        boot_time="알 수 없음"
    fi
    
    # 부팅 성공 여부 확인
    if [[ "$boot_status" == "normal" ]]; then
        local current_boot=$(journalctl -b 0 -n 1 --no-pager | grep -o 'Startup finished.*' | wc -l)
        if [[ $current_boot -gt 0 ]]; then
            boot_status="success"
        else
            boot_status="partial"
        fi
    fi
    
    echo "${boot_issues[@]}"
    echo "$boot_time"
    echo "$boot_status"
    
    log_diag "부팅 로그 분석 완료: $boot_status"
}

# 서비스 상태 분석
analyze_services() {
    log_step "서비스 상태 분석 중..."
    
    local service_info=()
    local failed_services=()
    local critical_services=("NetworkManager" "gdm" "systemd-logind" "dbus")
    
    # 실패한 서비스 확인
    local failed_output=$(systemctl list-units --failed --no-pager 2>/dev/null)
    if [[ -n "$failed_output" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ loaded.*failed.*not-found ]]; then
                local service=$(echo "$line" | awk '{print $1}')
                failed_services+=("$service:not-found")
            elif [[ "$line" =~ loaded.*failed.*activating ]]; then
                local service=$(echo "$line" | awk '{print $1}')
                failed_services+=("$service:activation-failed")
            fi
        done <<< "$failed_output"
    fi
    
    # 중요 서비스 상태 확인
    for service in "${critical_services[@]}"; do
        local status=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
        local enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "unknown")
        service_info["$service"]="$status:$enabled"
    done
    
    # 로드된 서비스 수
    local loaded_services=$(systemctl list-units --type=service --state=loaded --no-pager 2>/dev/null | wc -l)
    
    echo "${service_info[@]}"
    echo "${failed_services[@]}"
    echo "$loaded_services"
    
    log_diag "서비스 상태 분석 완료"
}

# 네트워크 상태 분석
analyze_network() {
    log_step "네트워크 상태 분석 중..."
    
    local network_info=()
    local network_issues=()
    
    # 네트워크 인터페이스 확인
    local interfaces=$(ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' ')
    
    for interface in $interfaces; do
        local status=$(ip link show "$interface" | grep -o 'state [A-Z]*' | cut -d' ' -f2)
        local has_ip=$(ip addr show "$interface" | grep -c 'inet ' | wc -l)
        
        if [[ "$status" == "DOWN" ]]; then
            network_issues+=("$interface:down")
        elif [[ $has_ip -eq 0 ]]; then
            network_issues+=("$interface:no-ip")
        fi
        
        network_info["$interface"]="$status:$has_ip"
    done
    
    # 인터넷 연결 테스트
    local internet_status="disconnected"
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        internet_status="connected"
    elif ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        internet_status="local-only"
    fi
    
    # DNS 확인
    local dns_status="unknown"
    if nslookup google.com &>/dev/null; then
        dns_status="working"
    else
        network_issues+=("dns:failed")
    fi
    
    echo "${network_info[@]}"
    echo "${network_issues[@]}"
    echo "$internet_status"
    echo "$dns_status"
    
    log_diag "네트워크 상태 분석 완료: $internet_status"
}

# 하드웨어 상태 분석
analyze_hardware() {
    log_step "하드웨어 상태 분석 중..."
    
    local hardware_info=()
    local hardware_issues=()
    
    # CPU 온도 확인 (lm-sensors)
    if command -v sensors &>/dev/null; then
        local temp_output=$(sensors 2>/dev/null | grep -E 'Core [0-9]+|Package id [0-9]+')
        if [[ -n "$temp_output" ]]; then
            local max_temp=$(echo "$temp_output" | grep -o '[0-9]+\.[0-9]+°C' | sort -nr | head -n1)
            if [[ $(echo "$max_temp" | cut -d. -f1) -gt 80 ]]; then
                hardware_issues+=("cpu:high-temperature:$max_temp")
            fi
            hardware_info[cpu_temp]="$max_temp"
        else
            hardware_info[cpu_temp]="unknown"
        fi
    else
        hardware_issues+=("cpu:no-sensors")
    fi
    
    # 디스크 상태 확인
    local root_device=$(findmnt -n -o SOURCE /)
    if [[ -b "$root_device" ]]; then
        # 디스크 사용량 확인
        local disk_usage=$(df -h "$root_device")
        local used_percent=$(echo "$disk_usage" | tail -n1 | awk '{print $5}' | sed 's/%//')
        
        if [[ ${used_percent%.*} -gt 90 ]]; then
            hardware_issues+=("disk:low-space:$used_percent")
        fi
        
        hardware_info[disk_usage]="$used_percent"
        
        # SSD 상태 확인
        if command -v smartctl &>/dev/null; then
            local smart_status=$(smartctl -H "$root_device" 2>/dev/null | grep -o 'overall-health: [A-Z]*' | cut -d: -f2)
            if [[ "$smart_status" != "PASSED" ]]; then
                hardware_issues+=("disk:smart-failure:$smart_status")
            fi
            hardware_info[disk_health]="$smart_status"
        fi
    fi
    
    # 메모리 상태 확인
    local mem_usage=$(free)
    local used_mem=$(echo "$mem_usage" | grep '^Mem:' | awk '{print $3}')
    local total_mem=$(echo "$mem_usage" | grep '^Mem:' | awk '{print $2}')
    local mem_percent=$((used_mem * 100 / total_mem))
    
    if [[ $mem_percent -gt 90 ]]; then
        hardware_issues+=("memory:high-usage:$mem_percent%")
    fi
    
    hardware_info[memory_usage]="$mem_percent%"
    
    echo "${hardware_info[@]}"
    echo "${hardware_issues[@]}"
    
    log_diag "하드웨어 상태 분석 완료"
}

# 로그 파일 분석
analyze_logs() {
    log_step "로그 파일 분석 중..."
    
    local log_analysis=()
    
    # 최근 오류 로그 수집
    local recent_errors=$(journalctl -p err -n 20 --no-pager 2>/dev/null | wc -l)
    local recent_warnings=$(journalctl -p warning -n 20 --no-pager 2>/dev/null | wc -l)
    local critical_errors=$(journalctl -p crit -n 10 --no-pager 2>/dev/null | wc -l)
    
    # 패키지 설치 오류
    local pacman_errors=""
    if [[ -f "/var/log/pacman.log" ]]; then
        pacman_errors=$(grep -c "error" /var/log/pacman.log 2>/dev/null || echo "0")
    fi
    
    # 보안 로그 분석
    local auth_failures=""
    if [[ -f "/var/log/auth.log" ]]; then
        auth_failures=$(grep -c "authentication failure" /var/log/auth.log 2>/dev/null || echo "0")
    fi
    
    log_analysis[errors]="$recent_errors"
    log_analysis[warnings]="$recent_warnings"
    log_analysis[critical]="$critical_errors"
    log_analysis[pacman_errors]="$pacman_errors"
    log_analysis[auth_failures]="$auth_failures"
    
    echo "${log_analysis[@]}"
    
    log_diag "로그 파일 분석 완료"
}

# 성능 벤치마크 수행
run_performance_benchmark() {
    log_step "성능 벤치마크 실행 중..."
    
    local benchmark_results=()
    
    # CPU 벤치마크 (간단한 테스트)
    local cpu_start=$(date +%s.%N)
    local cpu_test=$(dd if=/dev/zero bs=1M count=100 2>/dev/null | md5sum)
    local cpu_end=$(date +%s.%N)
    local cpu_time=$(echo "$cpu_end - $cpu_start" | bc 2>/dev/null || echo "unknown")
    benchmark_results[cpu_test]="$cpu_time"
    
    # 디스크 I/O 벤치마크
    local disk_start=$(date +%s.%N)
    local disk_test=$(dd if=/dev/zero of=/tmp/benchmark bs=1M count=100 2>/dev/null)
    local disk_end=$(date +%s.%N)
    local disk_time=$(echo "$disk_end - $disk_start" | bc 2>/dev/null || echo "unknown")
    rm -f /tmp/benchmark
    benchmark_results[disk_test]="$disk_time"
    
    # 메모리 속도 벤치마크
    local mem_start=$(date +%s.%N)
    local mem_test=$(dd if=/dev/zero of=/dev/null bs=1M count=100 2>/dev/null)
    local mem_end=$(date +%s.%N)
    local mem_time=$(echo "$mem_end - $mem_start" | bc 2>/dev/null || echo "unknown")
    benchmark_results[memory_test]="$mem_time"
    
    echo "${benchmark_results[@]}"
    
    log_diag "성능 벤치마크 완료"
}

# 통합 진단 보고서 생성
generate_diagnostic_report() {
    log_step "진단 보고서 생성 중..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local report_file="$REPORT_DIR/unifiedarch-diagnostic-$timestamp.html"
    
    # 데이터 수집
    local system_info=($(collect_system_info))
    local boot_info=($(analyze_boot_logs))
    local service_info=($(analyze_services))
    local network_info=($(analyze_network))
    local hardware_info=($(analyze_hardware))
    local log_info=($(analyze_logs))
    local benchmark_results=($(run_performance_benchmark))
    
    # HTML 보고서 생성
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UnifiedArch OS 시스템 진단 보고서</title>
    <style>
        body { font-family: 'Noto Sans', sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; color: #333; }
        .section { margin-bottom: 30px; }
        .section h2 { color: #2c3e50; border-bottom: 2px solid #2c3e50; padding-bottom: 10px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .card { background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #3498db; }
        .status-good { border-left-color: #27ae60; }
        .status-warning { border-left-color: #f39c12; }
        .status-error { border-left-color: #e74c3c; }
        .metric { display: flex; justify-content: space-between; margin: 10px 0; }
        .metric-label { font-weight: bold; color: #555; }
        .metric-value { color: #333; }
        .issues { background: #fff3cd; padding: 15px; border-radius: 5px; margin-top: 10px; }
        .issue { background: #e74c3c; color: white; padding: 5px 10px; margin: 5px 0; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 UnifiedArch OS 시스템 진단 보고서</h1>
            <p>생성 시간: $(date '+%Y년 %m월 %d일 %H:%M:%S')</p>
        </div>
        
        <div class="section">
            <h2>📊 시스템 정보</h2>
            <div class="grid">
                <div class="card">
                    <div class="metric">
                        <span class="metric-label">호스트 이름:</span>
                        <span class="metric-value">${system_info[hostname]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">커널 버전:</span>
                        <span class="metric-value">${system_info[kernel]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">아키텍처:</span>
                        <span class="metric-value">${system_info[arch]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">가동 시간:</span>
                        <span class="metric-value">${system_info[uptime]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">시스템 부하:</span>
                        <span class="metric-value">${system_info[load]}</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>💾 메모리 정보</h2>
            <div class="grid">
                <div class="card">
                    <div class="metric">
                        <span class="metric-label">전체 메모리:</span>
                        <span class="metric-value">${system_info[total_memory]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">사용 중:</span>
                        <span class="metric-value">${system_info[used_memory]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">가용 메모리:</span>
                        <span class="metric-value">${system_info[free_memory]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">스왑:</span>
                        <span class="metric-value">${system_info[swap_total]} (${system_info[swap_used]} 사용 중)</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>💻 CPU 정보</h2>
            <div class="grid">
                <div class="card">
                    <div class="metric">
                        <span class="metric-label">CPU 모델:</span>
                        <span class="metric-value">${system_info[cpu_model]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">코어 수:</span>
                        <span class="metric-value">${system_info[cpu_cores]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">스레드 수:</span>
                        <span class="metric-value">${system_info[cpu_threads]}</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>💾 디스크 정보</h2>
            <div class="grid">
                <div class="card">
                    <div class="metric">
                        <span class="metric-label">루트 장치:</span>
                        <span class="metric-value">${system_info[root_device]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">파일시스템:</span>
                        <span class="metric-value">${system_info[root_fs]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">전체 크기:</span>
                        <span class="metric-value">${system_info[root_size]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">사용 공간:</span>
                        <span class="metric-value">${system_info[root_used]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">가용 공간:</span>
                        <span class="metric-value">${system_info[root_available]}</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>🌐 네트워크 상태</h2>
            <div class="grid">
                <div class="card">
                    <div class="metric">
                        <span class="metric-label">인터넷 연결:</span>
                        <span class="metric-value">${network_info[3]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">DNS 상태:</span>
                        <span class="metric-value">${network_info[4]}</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>⚠️ 발견된 문제</h2>
            <div class="issues">
EOF
    
    # 문제 목록 추가
    local total_issues=0
    
    # 부팅 문제
    if [[ "${boot_info[2]}" != "success" ]]; then
        echo "                <div class=\"issue\">부팅 문제: ${boot_info[2]}</div>" >> "$report_file"
        total_issues=$((total_issues + 1))
    fi
    
    # 서비스 문제
    if [[ ${#service_info[@]} -gt 0 ]]; then
        for issue in "${service_info[@]}"; do
            echo "                <div class=\"issue\">서비스 문제: $issue</div>" >> "$report_file"
            total_issues=$((total_issues + 1))
        done
    fi
    
    # 네트워크 문제
    if [[ ${#network_info[@]} -gt 0 ]]; then
        for issue in "${network_info[@]}"; do
            echo "                <div class=\"issue\">네트워크 문제: $issue</div>" >> "$report_file"
            total_issues=$((total_issues + 1))
        done
    fi
    
    cat >> "$report_file" << 'EOF'
            </div>
        </div>
        
        <div class="section">
            <h2>📈 로그 분석</h2>
            <div class="grid">
                <div class="card">
                    <div class="metric">
                        <span class="metric-label">최근 오류:</span>
                        <span class="metric-value">${log_info[errors]}개</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">최근 경고:</span>
                        <span class="metric-value">${log_info[warnings]}개</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">치명 오류:</span>
                        <span class="metric-value">${log_info[critical]}개</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>🚀 성능 벤치마크</h2>
            <div class="grid">
                <div class="card">
                    <div class="metric">
                        <span class="metric-label">CPU 테스트:</span>
                        <span class="metric-value">${benchmark_results[cpu_test]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">디스크 I/O:</span>
                        <span class="metric-value">${benchmark_results[disk_test]}</span>
                    </div>
                    <div class="metric">
                        <span class="metric-label">메모리 속도:</span>
                        <span class="metric-value">${benchmark_results[memory_test]}</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>🔧 권장 조치</h2>
            <div class="card">
                <h3>시스템 최적화</h3>
                <ul>
                    <li>불필요한 서비스 비활성화: <code>systemctl disable &lt;service&gt;</code></li>
                    <li>패키지 캐시 정리: <code>sudo pacman -Scc</code></li>
                    <li>시스템 업데이트: <code>sudo pacman -Syu</code></li>
                </ul>
                
                <h3>네트워크 문제 해결</h3>
                <ul>
                    <li>네트워크 재시작: <code>sudo systemctl restart NetworkManager</code></li>
                    <li>DNS 설정 확인: <code>cat /etc/resolv.conf</code></li>
                    <li>방화벽 상태: <code>sudo ufw status</code></li>
                </ul>
                
                <h3>하드웨어 문제 해결</h3>
                <ul>
                    <li>디스크 공간 확보: <code>sudo pacman -Scc</code></li>
                    <li>온도 관리: <code>sensors</code></li>
                    <li>하드웨어 정보: <code>lspci</code>, <code>lsusb</code></li>
                </ul>
            </div>
        </div>
        
        <div style="text-align: center; margin-top: 30px; color: #666;">
            <p>보고서 생성: $(date '+%Y년 %m월 %d일 %H:%M:%S')</p>
            <p>UnifiedArch OS 시스템 진단 도구 v1.0</p>
        </div>
    </div>
</body>
</html>
EOF
    
    log_success "진단 보고서 생성 완료: $report_file"
    echo "$report_file"
}

# 실시간 모니터링 모드
start_realtime_monitoring() {
    log_step "실시간 모니터링 시작 중..."
    
    # 웹 서버 시작 (간단한)
    local monitor_port=8080
    local monitor_dir="/tmp/unifiedarch-monitor"
    mkdir -p "$monitor_dir"
    
    cat > "$monitor_dir/monitor.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>UnifiedArch OS 실시간 모니터</title>
    <script>
        function updateStats() {
            fetch('/api/stats')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('cpu').textContent = data.cpu || 'N/A';
                    document.getElementById('memory').textContent = data.memory || 'N/A';
                    document.getElementById('network').textContent = data.network || 'N/A';
                })
                .catch(error => console.error('Error:', error));
        }
        
        setInterval(updateStats, 5000);
        window.onload = updateStats;
    </script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #1a1a1a; color: #fff; }
        .container { max-width: 800px; margin: 0 auto; }
        .stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
        .stat { background: #2d3748; padding: 20px; border-radius: 8px; text-align: center; }
        .stat h3 { margin: 0 0 10px 0; color: #64b5f6; }
        .stat .value { font-size: 2em; font-weight: bold; color: #4ade80; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖥️ UnifiedArch OS 실시간 모니터</h1>
        <div class="stats">
            <div class="stat">
                <h3>CPU</h3>
                <div class="value" id="cpu">로딩 중...</div>
            </div>
            <div class="stat">
                <h3>메모리</h3>
                <div class="value" id="memory">로딩 중...</div>
            </div>
            <div class="stat">
                <h3>네트워크</h3>
                <div class="value" id="network">로딩 중...</div>
            </div>
        </div>
    </div>
</body>
</html>
EOF
    
    # 간단한 HTTP 서버 시작
    cd "$monitor_dir"
    python3 -m http.server $monitor_port &
    local server_pid=$!
    
    log_success "실시간 모니터링 시작: http://localhost:$monitor_port"
    log_info "PID: $server_pid"
    log_info "중지하려면 Ctrl+C"
    
    # API 엔드포인트 (간단한)
    cat > "$monitor_dir/api.py" << 'EOF'
#!/usr/bin/env python3
import json
import subprocess
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

class StatsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/stats':
            stats = self.get_system_stats()
            self.send_response(200, 'application/json', json.dumps(stats))
        else:
            self.send_response(404, 'text/plain', 'Not Found')
    
    def send_response(self, status, content_type, content):
        self.send_response(status)
        self.send_header('Content-type', content_type)
        self.end_headers()
        self.wfile.write(content.encode())
    
    def get_system_stats(self):
        try:
            # CPU 사용률
            cpu_usage = subprocess.check_output(['top', '-bn1', '|', 'grep', 'Cpu'], text=True).strip()
            
            # 메모리 사용률
            mem_info = subprocess.check_output(['free', '-h'], text=True).strip().split('\n')[1]
            
            # 네트워크 상태
            network_status = "connected" if subprocess.call(['ping', '-c', '1', '8.8.8.8'], stdout=subprocess.DEVNULL) == 0 else "disconnected"
            
            return {
                'cpu': cpu_usage,
                'memory': mem_info,
                'network': network_status,
                'timestamp': time.time()
            }
        except Exception as e:
            return {'error': str(e)}

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8081), StatsHandler)
    print("API server started on http://localhost:8081")
    server.serve_forever()
EOF
    
    python3 "$monitor_dir/api.py" &
    local api_pid=$!
    
    # 정리 함수
    cleanup() {
        log_info "모니터링 서버 정리 중..."
        kill $server_pid 2>/dev/null
        kill $api_pid 2>/dev/null
        rm -rf "$monitor_dir"
        exit 0
    }
    
    trap cleanup SIGINT SIGTERM
    
    wait
}

# 도움말
show_help() {
    echo "UnifiedArch OS System Diagnostics Tool"
    echo ""
    echo "사용법: $0 [명령어] [인자]"
    echo ""
    echo "명령어:"
    echo "  full              - 전체 진단 및 보고서 생성"
    echo "  quick             - 빠른 진단"
    echo "  boot              - 부팅 로그 분석"
    echo "  services          - 서비스 상태 분석"
    echo "  network           - 네트워크 상태 분석"
    echo "  hardware          - 하드웨어 상태 분석"
    echo "  logs              - 로그 파일 분석"
    echo "  benchmark         - 성능 벤치마크"
    echo "  monitor           - 실시간 모니터링 시작"
    echo "  help              - 이 도움말"
    echo ""
    echo "예시:"
    echo "  $0 full                    - 전체 진단 실행"
    echo "  $0 monitor                 - 실시간 모니터링 시작"
    echo ""
    echo "보고서 저장 위치: /var/lib/unifiedarch/reports/"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    check_root
    create_directories
    
    case "$action" in
        full)
            log_info "전체 시스템 진단 시작..."
            generate_diagnostic_report
            ;;
        quick)
            log_info "빠른 시스템 진단 시작..."
            collect_system_info > /dev/null
            analyze_boot_logs > /dev/null
            analyze_services > /dev/null
            analyze_network > /dev/null
            analyze_hardware > /dev/null
            log_success "빠른 진단 완료"
            ;;
        boot)
            analyze_boot_logs
            ;;
        services)
            analyze_services
            ;;
        network)
            analyze_network
            ;;
        hardware)
            analyze_hardware
            ;;
        logs)
            analyze_logs
            ;;
        benchmark)
            run_performance_benchmark
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
