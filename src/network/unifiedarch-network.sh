#!/bin/bash
# UnifiedArch OS 네트워크 관리 시스템
# 완벽한 네트워크 설정 및 관리

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
CONFIG_DIR="/etc/unifiedarch/network"
PROFILES_DIR="$CONFIG_DIR/profiles"
ACTIVE_PROFILE="$CONFIG_DIR/active.profile"

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

# 네트워크 인터페이스 목록 가져오기
get_network_interfaces() {
    ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}' | sed 's/@.*//'
}

# 네트워크 연결 상태 확인
check_network_status() {
    local interfaces=($(get_network_interfaces))
    local connected_interfaces=()
    
    for interface in "${interfaces[@]}"; do
        if ip link show "$interface" | grep -q "state UP"; then
            local ip_addr=$(ip addr show "$interface" | grep "inet " | awk '{print $2}' | head -1)
            if [[ -n "$ip_addr" ]]; then
                connected_interfaces+=("$interface: $ip_addr")
            fi
        fi
    done
    
    echo "${connected_interfaces[@]}"
}

# 네트워크 프로필 생성
create_network_profile() {
    local profile_name="$1"
    local interface="${2:-auto}"
    local ip_type="${3:-dhcp}"
    local ip_address="${4:-}"
    local gateway="${5:-}"
    local dns="${6:-8.8.8.8,8.8.4.4}"
    
    if [[ -z "$profile_name" ]]; then
        log_error "프로필 이름이 필요합니다"
        return 1
    fi
    
    mkdir -p "$PROFILES_DIR"
    local profile_file="$PROFILES_DIR/${profile_name}.profile"
    
    cat > "$profile_file" << EOF
# UnifiedArch OS 네트워크 프로필
# 프로필 이름: $profile_name

PROFILE_NAME="$profile_name"
INTERFACE="$interface"
IP_TYPE="$ip_type"

# 고정 IP 설정
IP_ADDRESS="$ip_address"
GATEWAY="$gateway"
DNS_SERVERS="$dns"

# 추가 설정
AUTO_CONNECT="false"
PRIORITY="50"
METRIC="100"

# 보안 설정
ENABLE_FIREWALL="true"
ENABLE_MAC_SPOOFING="false"
MAC_ADDRESS=""

# 무선 설정 (해당하는 경우)
SSID=""
WPA_SECURITY=""
WPA_PASSWORD=""
EOF
    
    log_success "네트워크 프로필 생성됨: $profile_name"
    log_info "프로필 파일: $profile_file"
}

# 네트워크 프로필 목록 보기
list_network_profiles() {
    echo "=== UnifiedArch OS 네트워크 프로필 ==="
    echo ""
    
    if [[ ! -d "$PROFILES_DIR" ]]; then
        log_info "프로필 디렉토리 없음: $PROFILES_DIR"
        return 0
    fi
    
    local profiles=("$PROFILES_DIR"/*.profile)
    if [[ ${#profiles[@]} -eq 0 || ! -f "${profiles[0]}" ]]; then
        log_info "생성된 프로필이 없습니다"
        return 0
    fi
    
    for profile_file in "${profiles[@]}"; do
        if [[ -f "$profile_file" ]]; then
            local profile_name=$(basename "$profile_file" .profile)
            echo "프로필: $profile_name"
            
            # 프로필 정보 표시
            if source "$profile_file" 2>/dev/null; then
                echo "  인터페이스: ${INTERFACE:-auto}"
                echo "  IP 타입: ${IP_TYPE:-dhcp}"
                if [[ "$IP_TYPE" == "static" ]]; then
                    echo "  IP 주소: ${IP_ADDRESS:-설정안됨}"
                    echo "  게이트웨이: ${GATEWAY:-설정안됨}"
                fi
                echo "  DNS: ${DNS_SERVERS:-8.8.8.8,8.8.4.4}"
                echo "  자동 연결: ${AUTO_CONNECT:-false}"
                echo ""
            fi
        fi
    done
}

# 네트워크 프로필 적용
apply_network_profile() {
    local profile_name="$1"
    
    if [[ -z "$profile_name" ]]; then
        log_error "프로필 이름이 필요합니다"
        return 1
    fi
    
    local profile_file="$PROFILES_DIR/${profile_name}.profile"
    
    if [[ ! -f "$profile_file" ]]; then
        log_error "프로필 파일 없음: $profile_file"
        return 1
    fi
    
    # 프로필 설정 로드
    source "$profile_file"
    
    log_info "네트워크 프로필 적용 중: $profile_name"
    
    # 인터페이스 결정
    local target_interface="$INTERFACE"
    if [[ "$target_interface" == "auto" ]]; then
        # 첫 번째 활성 인터페이스 사용
        target_interface=$(get_network_interfaces | head -1)
        log_info "자동 인터페이스 선택: $target_interface"
    fi
    
    if [[ -z "$target_interface" ]]; then
        log_error "사용 가능한 네트워크 인터페이스 없음"
        return 1
    fi
    
    # 기존 연결 해제
    log_info "기존 네트워크 연결 해제 중..."
    ip link set "$target_interface" down 2>/dev/null || true
    
    # IP 설정 적용
    case "$IP_TYPE" in
        "dhcp")
            log_info "DHCP 설정 적용 중..."
            dhclient "$target_interface" 2>/dev/null || \
            dhcpcd "$target_interface" 2>/dev/null || \
            {
                log_warning "DHCP 클라이언트를 찾을 수 없습니다. 수동 설정 시도..."
                ip link set "$target_interface" up
            }
            ;;
        "static")
            if [[ -n "$IP_ADDRESS" ]]; then
                log_info "고정 IP 설정 적용 중: $IP_ADDRESS"
                ip link set "$target_interface" up
                ip addr add "$IP_ADDRESS" dev "$target_interface"
                
                if [[ -n "$GATEWAY" ]]; then
                    ip route add default via "$GATEWAY" dev "$target_interface"
                fi
                
                if [[ -n "$DNS_SERVERS" ]]; then
                    setup_dns "$DNS_SERVERS"
                fi
            else
                log_error "고정 IP 주소가 설정되지 않았습니다"
                return 1
            fi
            ;;
        *)
            log_error "알 수 없는 IP 타입: $IP_TYPE"
            return 1
            ;;
    esac
    
    # 활성 프로필 저장
    echo "$profile_name" > "$ACTIVE_PROFILE"
    
    # 방화벽 설정
    if [[ "${ENABLE_FIREWALL:-true}" == "true" ]]; then
        setup_firewall "$target_interface"
    fi
    
    log_success "네트워크 프로필 적용 완료: $profile_name"
    
    # 연결 상태 확인
    sleep 3
    show_network_status
}

# DNS 설정
setup_dns() {
    local dns_servers="$1"
    
    log_info "DNS 서버 설정 중: $dns_servers"
    
    # resolv.conf 백업
    if [[ -f "/etc/resolv.conf" ]]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup
    fi
    
    # 새 DNS 설정
    > /etc/resolv.conf
    IFS=',' read -ra dns_array <<< "$dns_servers"
    for dns in "${dns_array[@]}"; do
        echo "nameserver $dns" >> /etc/resolv.conf
    done
    
    log_success "DNS 설정 완료"
}

# 방화벽 설정
setup_firewall() {
    local interface="$1"
    
    log_info "방화벽 설정 중..."
    
    if command -v ufw >/dev/null 2>&1; then
        # UFW 사용
        ufw --force reset 2>/dev/null || true
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow in on "$interface" from any to any port 22  # SSH
        ufw allow in on "$interface" from any to any port 80  # HTTP
        ufw allow in on "$interface" from any to any port 443 # HTTPS
        ufw --force enable
        log_success "UFW 방화벽 설정 완료"
    elif command -v iptables >/dev/null 2>&1; then
        # iptables 사용
        iptables -F
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT ACCEPT
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT  # SSH
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT  # HTTP
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT # HTTPS
        log_success "iptables 방화벽 설정 완료"
    else
        log_warning "방화벽 도구를 찾을 수 없습니다"
    fi
}

# 네트워크 상태 보기
show_network_status() {
    echo "=== UnifiedArch OS 네트워크 상태 ==="
    echo ""
    
    # 인터페이스 정보
    echo "네트워크 인터페이스:"
    get_network_interfaces | while read -r interface; do
        local status=$(ip link show "$interface" | grep -o "state [A-Z]*" | cut -d' ' -f2)
        local ip_addr=$(ip addr show "$interface" | grep "inet " | awk '{print $2}' | head -1)
        local mac_addr=$(ip link show "$interface" | grep -o "link/ether [a-f0-9:]*" | cut -d' ' -f2)
        
        echo -n "  $interface: "
        if [[ "$status" == "UP" ]]; then
            echo -e "${GREEN}UP${NC} ($ip_addr)"
        else
            echo -e "${RED}DOWN${NC}"
        fi
        echo "    MAC: $mac_addr"
    done
    echo ""
    
    # 라우팅 정보
    echo "라우팅 테이블:"
    ip route | head -10
    echo ""
    
    # DNS 정보
    echo "DNS 설정:"
    if [[ -f "/etc/resolv.conf" ]]; then
        grep "^nameserver" /etc/resolv.conf | head -3
    else
        echo "  DNS 설정 없음"
    fi
    echo ""
    
    # 인터넷 연결 테스트
    echo "인터넷 연결 테스트:"
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "  Google DNS: ${GREEN}연결됨${NC}"
    else
        echo -e "  Google DNS: ${RED}연결 실패${NC}"
    fi
    
    if ping -c 1 1.1.1.1 >/dev/null 2>&1; then
        echo -e "  Cloudflare DNS: ${GREEN}연결됨${NC}"
    else
        echo -e "  Cloudflare DNS: ${RED}연결 실패${NC}"
    fi
    
    echo ""
    
    # 활성 프로필
    if [[ -f "$ACTIVE_PROFILE" ]]; then
        echo "활성 프로필: $(cat "$ACTIVE_PROFILE")"
    else
        echo "활성 프로필: 없음"
    fi
}

# 무선 네트워크 스캔
scan_wireless_networks() {
    echo "=== 무선 네트워크 스캔 ==="
    echo ""
    
    if ! command -v iwlist >/dev/null 2>&1 && ! command -v iw >/dev/null 2>&1; then
        log_error "무선 네트워크 도구를 찾을 수 없습니다"
        return 1
    fi
    
    local wireless_interfaces=($(get_network_interfaces | grep -E "wl|wlan"))
    
    if [[ ${#wireless_interfaces[@]} -eq 0 ]]; then
        log_warning "무선 네트워크 인터페이스 없음"
        return 1
    fi
    
    for interface in "${wireless_interfaces[@]}"; do
        echo "인터페이스: $interface"
        echo "스캔 중..."
        
        if command -v iw >/dev/null 2>&1; then
            iw dev "$interface" scan | grep -E "SSID|signal|frequency" | head -20
        elif command -v iwlist >/dev/null 2>&1; then
            iwlist "$interface" scan | grep -E "ESSID|Quality|Frequency" | head -20
        fi
        
        echo ""
    done
}

# 네트워크 속도 테스트
test_network_speed() {
    echo "=== 네트워크 속도 테스트 ==="
    echo ""
    
    # 기본 연속성 테스트
    log_info "연속성 테스트 중..."
    local ping_result=$(ping -c 4 8.8.8.8 2>/dev/null | tail -1)
    if [[ -n "$ping_result" ]]; then
        local avg_ping=$(echo "$ping_result" | grep -o "avg = [0-9.]*" | cut -d' ' -f3)
        echo -e "평균 핑: ${GREEN}${avg_ping}ms${NC}"
    else
        echo -e "핑 테스트: ${RED}실패${NC}"
    fi
    
    # 다운로드 속도 테스트 (speedtest-cli가 있는 경우)
    if command -v speedtest-cli >/dev/null 2>&1; then
        log_info "다운로드 속도 테스트 중..."
        local speed_result=$(speedtest-cli --simple 2>/dev/null)
        if [[ -n "$speed_result" ]]; then
            echo "$speed_result"
        else
            log_warning "속도 테스트 실패"
        fi
    else
        log_info "간단한 다운로드 테스트 중..."
        local start_time=$(date +%s.%N)
        wget -O /dev/null http://speedtest.wdc01.softlayer.com/downloads/test10.zip 2>/dev/null
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "알 수 없음")
        echo "다운로드 테스트 시간: ${duration}초"
    fi
    
    # 대역폭 사용량
    echo ""
    echo "네트워크 인터페이스 대역폭:"
    cat /proc/net/dev | grep -E "eth|wlan|enp" | head -5 | while read -r line; do
        local interface=$(echo "$line" | cut -d: -f1)
        local rx_bytes=$(echo "$line" | awk '{print $2}')
        local tx_bytes=$(echo "$line" | awk '{print $10}')
        
        if [[ -n "$interface" && "$rx_bytes" != "0" ]]; then
            echo "  $interface: RX: ${rx_bytes} bytes, TX: ${tx_bytes} bytes"
        fi
    done
}

# 네트워크 문제 진단
diagnose_network() {
    echo "=== 네트워크 문제 진단 ==="
    echo ""
    
    # 1. 인터페이스 상태
    log_info "1. 네트워크 인터페이스 상태 확인..."
    local interfaces=($(get_network_interfaces))
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        log_error "네트워크 인터페이스 없음"
        return 1
    fi
    
    for interface in "${interfaces[@]}"; do
        local status=$(ip link show "$interface" | grep -o "state [A-Z]*" | cut -d' ' -f2)
        echo "  $interface: $status"
    done
    
    # 2. 드라이버 확인
    log_info "2. 네트워크 드라이버 확인..."
    for interface in "${interfaces[@]}"; do
        local driver=$(ethtool -i "$interface" 2>/dev/null | grep "driver" | cut -d: -f2 | xargs || echo "알 수 없음")
        echo "  $interface 드라이버: $driver"
    done
    
    # 3. IP 주소 확인
    log_info "3. IP 주소 할당 확인..."
    for interface in "${interfaces[@]}"; do
        local ip_addr=$(ip addr show "$interface" | grep "inet " | awk '{print $2}' | head -1)
        if [[ -n "$ip_addr" ]]; then
            echo "  $interface: $ip_addr"
        else
            echo "  $interface: IP 주소 없음"
        fi
    done
    
    # 4. 게이트웨이 확인
    log_info "4. 게이트웨이 확인..."
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    if [[ -n "$gateway" ]]; then
        echo "  게이트웨이: $gateway"
        if ping -c 1 "$gateway" >/dev/null 2>&1; then
            echo -e "  게이트웨이 연결: ${GREEN}정상${NC}"
        else
            echo -e "  게이트웨이 연결: ${RED}실패${NC}"
        fi
    else
        echo "  게이트웨이: 없음"
    fi
    
    # 5. DNS 확인
    log_info "5. DNS 확인..."
    if [[ -f "/etc/resolv.conf" ]]; then
        local dns_servers=$(grep "^nameserver" /etc/resolv.conf | head -2)
        echo "  DNS 서버:"
        echo "$dns_servers" | sed 's/^/    /'
        
        # DNS 해상 테스트
        if nslookup google.com >/dev/null 2>&1; then
            echo -e "  DNS 해상: ${GREEN}정상${NC}"
        else
            echo -e "  DNS 해상: ${RED}실패${NC}"
        fi
    else
        echo "  DNS 설정 없음"
    fi
    
    # 6. 외부 연결 확인
    log_info "6. 외부 연결 확인..."
    local test_hosts=("8.8.8.8" "1.1.1.1" "google.com")
    for host in "${test_hosts[@]}"; do
        if ping -c 1 "$host" >/dev/null 2>&1; then
            echo -e "  $host: ${GREEN}연결됨${NC}"
        else
            echo -e "  $host: ${RED}연결 실패${NC}"
        fi
    done
}

# 네트워크 설정 초기화
reset_network() {
    log_warning "네트워크 설정 초기화 중..."
    
    # 모든 인터페이스 다운
    for interface in $(get_network_interfaces); do
        ip link set "$interface" down 2>/dev/null || true
        ip addr flush dev "$interface" 2>/dev/null || true
    done
    
    # 라우팅 테이블 초기화
    ip route flush all 2>/dev/null || true
    
    # 방화벽 초기화
    if command -v ufw >/dev/null 2>&1; then
        ufw --force reset 2>/dev/null || true
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        iptables -F 2>/dev/null || true
        iptables -X 2>/dev/null || true
        iptables -t nat -F 2>/dev/null || true
    fi
    
    # DNS 초기화
    if [[ -f "/etc/resolv.conf.backup" ]]; then
        mv /etc/resolv.conf.backup /etc/resolv.conf
    else
        > /etc/resolv.conf
    fi
    
    # 활성 프로필 제거
    rm -f "$ACTIVE_PROFILE"
    
    log_success "네트워크 설정 초기화 완료"
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 네트워크 관리 시스템"
    echo ""
    echo "사용법: $0 [명령] [인자...]"
    echo ""
    echo "명령:"
    echo "  status                    - 네트워크 상태 보기"
    echo "  profile create <name>      - 프로필 생성"
    echo "  profile list              - 프로필 목록 보기"
    echo "  profile apply <name>      - 프로필 적용"
    echo "  scan                     - 무선 네트워크 스캔"
    echo "  speed                    - 네트워크 속도 테스트"
    echo "  diagnose                 - 네트워크 문제 진단"
    echo "  reset                    - 네트워크 설정 초기화"
    echo "  help                     - 이 도움말 표시"
    echo ""
    echo "프로필 생성 인자:"
    echo "  $0 profile create <name> [interface] [ip_type] [ip] [gateway] [dns]"
    echo ""
    echo "예시:"
    echo "  $0 status                           - 상태 확인"
    echo "  $0 profile create home eth0 static 192.168.1.100 192.168.1.1 8.8.8.8"
    echo "  $0 profile apply home                 - home 프로필 적용"
    echo "  $0 scan                            - 무선 네트워크 스캔"
    echo "  $0 speed                           - 속도 테스트"
    echo "  $0 diagnose                        - 문제 진단"
}

# 메인 함수
main() {
    local command="${1:-help}"
    
    # 설정 디렉토리 생성
    mkdir -p "$CONFIG_DIR" "$PROFILES_DIR"
    
    case "$command" in
        "status")
            show_network_status
            ;;
        "profile")
            local subcommand="${2:-help}"
            case "$subcommand" in
                "create")
                    create_network_profile "${3:-}" "${4:-auto}" "${5:-dhcp}" "${6:-}" "${7:-}" "${8:-8.8.8.8,8.8.4.4}"
                    ;;
                "list")
                    list_network_profiles
                    ;;
                "apply")
                    apply_network_profile "${3:-}"
                    ;;
                *)
                    log_error "알 수 없는 프로필 명령: $subcommand"
                    show_help
                    exit 1
                    ;;
            esac
            ;;
        "scan")
            scan_wireless_networks
            ;;
        "speed")
            test_network_speed
            ;;
        "diagnose")
            diagnose_network
            ;;
        "reset")
            reset_network
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
