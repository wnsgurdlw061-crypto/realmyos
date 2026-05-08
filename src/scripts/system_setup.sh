#!/bin/bash
# Massive OS 시스템 설정 스크립트
# System Setup Script

set -euo pipefail

# 스크립트 정보
SCRIPT_NAME="system_setup.sh"
SCRIPT_VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/system_config.yaml"
LOG_FILE="/var/log/massive_os_setup.log"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 로깅 함수
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} ${message}" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} ${message}" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${message}" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} ${message}" ;;
    esac
}

# 권한 체크
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "이 스크립트는 root 권한으로 실행해야 합니다."
        exit 1
    fi
}

# 시스템 정보 표시
show_system_info() {
    log "INFO" "=== Massive OS 시스템 설정 ==="
    log "INFO" "스크립트 버전: ${SCRIPT_VERSION}"
    log "INFO" "커널 버전: $(uname -r)"
    log "INFO" "아키텍처: $(uname -m)"
    log "INFO" "호스트네임: $(hostname)"
    log "INFO" "메모리: $(free -h | grep '^Mem:' | awk '{print $2}')"
    log "INFO" "디스크: $(df -h / | tail -1 | awk '{print $2}')"
    echo
}

# 설정 파일 체크
check_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log "ERROR" "설정 파일을 찾을 수 없습니다: ${CONFIG_FILE}"
        exit 1
    fi
    
    log "INFO" "설정 파일 확인: ${CONFIG_FILE}"
}

# 네트워크 설정
setup_network() {
    log "INFO" "네트워크 설정 중..."
    
    # 호스트네임 설정
    local hostname=$(yq eval '.system.hostname' "${CONFIG_FILE}")
    if [[ -n "${hostname}" && "${hostname}" != "null" ]]; then
        hostnamectl set-hostname "${hostname}"
        log "INFO" "호스트네임 설정: ${hostname}"
    fi
    
    # /etc/hosts 설정
    cat > /etc/hosts << EOF
127.0.0.1   localhost
127.0.1.1   $(hostname) localhost.localdomain localhost
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    
    # 네트워크 인터페이스 설정
    local interfaces_count=$(yq eval '.network.interfaces | length' "${CONFIG_FILE}")
    for ((i=0; i<interfaces_count; i++)); do
        local name=$(yq eval ".network.interfaces[${i}].name" "${CONFIG_FILE}")
        local method=$(yq eval ".network.interfaces[${i}].method" "${CONFIG_FILE}")
        local auto=$(yq eval ".network.interfaces[${i}].auto" "${CONFIG_FILE}")
        
        if [[ "${name}" != "null" && "${method}" != "null" ]]; then
            local config_file="/etc/systemd/network/10-${name}.network"
            
            cat > "${config_file}" << EOF
[Match]
Name=${name}

[Network]
EOF
            
            if [[ "${method}" == "dhcp" ]]; then
                echo "DHCP=yes" >> "${config_file}"
            elif [[ "${method}" == "static" ]]; then
                local address=$(yq eval ".network.interfaces[${i}].address" "${CONFIG_FILE}")
                local netmask=$(yq eval ".network.interfaces[${i}].netmask" "${CONFIG_FILE}")
                local gateway=$(yq eval ".network.interfaces[${i}].gateway" "${CONFIG_FILE}")
                
                if [[ "${address}" != "null" ]]; then
                    echo "Address=${address}" >> "${config_file}"
                fi
                if [[ "${gateway}" != "null" ]]; then
                    echo "Gateway=${gateway}" >> "${config_file}"
                fi
            fi
            
            log "INFO" "네트워크 인터페이스 설정: ${name} (${method})"
        fi
    done
    
    # systemd-networkd 활성화
    systemctl enable systemd-networkd
    systemctl restart systemd-networkd
    
    log "INFO" "네트워크 설정 완료"
}

# 스토리지 설정
setup_storage() {
    log "INFO" "스토리지 설정 중..."
    
    # 파티션 마운트 설정
    local partitions_count=$(yq eval '.storage.disks[0].partitions | length' "${CONFIG_FILE}")
    for ((i=0; i<partitions_count; i++)); do
        local mount_point=$(yq eval ".storage.disks[0].partitions[${i}].mount_point" "${CONFIG_FILE}")
        local filesystem=$(yq eval ".storage.disks[0].partitions[${i}].filesystem" "${CONFIG_FILE}")
        local options=$(yq eval ".storage.disks[0].partitions[${i}].options | join(\",\")" "${CONFIG_FILE}")
        
        if [[ "${mount_point}" != "null" && "${mount_point}" != "/" && "${filesystem}" != "swap" ]]; then
            # 마운트 디렉토리 생성
            mkdir -p "${mount_point}"
            
            # fstab에 추가
            local fstab_entry="${mount_point}    ${mount_point}    ${filesystem}"
            if [[ "${options}" != "null" && -n "${options}" ]]; then
                fstab_entry="${fstab_entry}    ${options}"
            else
                fstab_entry="${fstab_entry}    defaults"
            fi
            fstab_entry="${fstab_entry}    0    0"
            
            if ! grep -q "${mount_point}" /etc/fstab; then
                echo "${fstab_entry}" >> /etc/fstab
                log "INFO" "fstab에 추가: ${fstab_entry}"
            fi
        fi
    done
    
    # 스왑 설정
    local swap_size=$(yq eval '.storage.disks[0].partitions[] | select(.type == "swap") | .size' "${CONFIG_FILE}")
    if [[ "${swap_size}" != "null" && -n "${swap_size}" ]]; then
        # 스왑 파일 생성 (필요한 경우)
        if [[ ! -f /swapfile ]]; then
            local swap_size_mb=$(echo "${swap_size}" | sed 's/G//')
            swap_size_mb=$((swap_size_mb * 1024))
            
            log "INFO" "스왑 파일 생성 중: ${swap_size} (${swap_size_mb}MB)"
            fallocate -l "${swap_size_mb}M" /swapfile
            chmod 600 /swapfile
            mkswap /swapfile
            swapon /swapfile
            
            # fstab에 추가
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            log "INFO" "스왑 파일 활성화 완료"
        fi
    fi
    
    log "INFO" "스토리지 설정 완료"
}

# 사용자 설정
setup_users() {
    log "INFO" "사용자 설정 중..."
    
    # 그룹 생성
    local default_groups=$(yq eval '.users.default_groups | join(" ")' "${CONFIG_FILE}")
    for group in ${default_groups}; do
        if ! getent group "${group}" >/dev/null 2>&1; then
            groupadd "${group}"
            log "INFO" "그룹 생성: ${group}"
        fi
    done
    
    # 사용자 생성
    local users_count=$(yq eval '.users.users | length' "${CONFIG_FILE}")
    for ((i=0; i<users_count; i++)); do
        local username=$(yq eval ".users.users[${i}].username" "${CONFIG_FILE}")
        local uid=$(yq eval ".users.users[${i}].uid" "${CONFIG_FILE}")
        local gid=$(yq eval ".users.users[${i}].gid" "${CONFIG_FILE}")
        local home=$(yq eval ".users.users[${i}].home" "${CONFIG_FILE}")
        local shell=$(yq eval ".users.users[${i}].shell" "${CONFIG_FILE}")
        local groups=$(yq eval ".users.users[${i}].groups | join(\",\")" "${CONFIG_FILE}")
        local sudo_access=$(yq eval ".users.users[${i}].sudo_access" "${CONFIG_FILE}")
        local create_home=$(yq eval ".users.users[${i}].create_home" "${CONFIG_FILE}")
        
        if [[ "${username}" != "null" && "${username}" != "root" ]]; then
            if ! id "${username}" >/dev/null 2>&1; then
                local useradd_cmd="useradd"
                
                if [[ "${uid}" != "null" ]]; then
                    useradd_cmd="${useradd_cmd} -u ${uid}"
                fi
                
                if [[ "${gid}" != "null" ]]; then
                    useradd_cmd="${useradd_cmd} -g ${gid}"
                fi
                
                if [[ "${home}" != "null" ]]; then
                    useradd_cmd="${useradd_cmd} -d ${home}"
                fi
                
                if [[ "${shell}" != "null" ]]; then
                    useradd_cmd="${useradd_cmd} -s ${shell}"
                fi
                
                if [[ "${create_home}" == "true" ]]; then
                    useradd_cmd="${useradd_cmd} -m"
                fi
                
                useradd_cmd="${useradd_cmd} ${username}"
                
                eval "${useradd_cmd}"
                log "INFO" "사용자 생성: ${username}"
                
                # 그룹에 추가
                if [[ "${groups}" != "null" && -n "${groups}" ]]; then
                    usermod -G "${groups}" "${username}"
                    log "INFO" "사용자 그룹 설정: ${username} -> ${groups}"
                fi
                
                # sudo 권한 설정
                if [[ "${sudo_access}" == "true" ]]; then
                    echo "${username} ALL=(ALL) ALL" >> /etc/sudoers.d/"${username}"
                    chmod 440 /etc/sudoers.d/"${username}"
                    log "INFO" "sudo 권한 부여: ${username}"
                fi
            fi
        fi
    done
    
    log "INFO" "사용자 설정 완료"
}

# 서비스 설정
setup_services() {
    log "INFO" "서비스 설정 중..."
    
    # 활성화할 서비스
    local enabled_services=$(yq eval '.services.enabled | join(" ")' "${CONFIG_FILE}")
    for service in ${enabled_services}; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            systemctl enable "${service}"
            systemctl start "${service}"
            log "INFO" "서비스 활성화: ${service}"
        fi
    done
    
    # 비활성화할 서비스
    local disabled_services=$(yq eval '.services.disabled | join(" ")' "${CONFIG_FILE}")
    for service in ${disabled_services}; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            systemctl disable "${service}"
            systemctl stop "${service}" 2>/dev/null || true
            log "INFO" "서비스 비활성화: ${service}"
        fi
    done
    
    # 커스텀 서비스 생성
    local custom_services_count=$(yq eval '.services.custom_services | length' "${CONFIG_FILE}")
    for ((i=0; i<custom_services_count; i++)); do
        local name=$(yq eval ".services.custom_services[${i}].name" "${CONFIG_FILE}")
        local description=$(yq eval ".services.custom_services[${i}].description" "${CONFIG_FILE}")
        local exec_start=$(yq eval ".services.custom_services[${i}].exec_start" "${CONFIG_FILE}")
        local exec_reload=$(yq eval ".services.custom_services[${i}].exec_reload" "${CONFIG_FILE}")
        local restart=$(yq eval ".services.custom_services[${i}].restart" "${CONFIG_FILE}")
        local user=$(yq eval ".services.custom_services[${i}].user" "${CONFIG_FILE}")
        local group=$(yq eval ".services.custom_services[${i}].group" "${CONFIG_FILE}")
        
        if [[ "${name}" != "null" && "${exec_start}" != "null" ]]; then
            local service_file="/etc/systemd/system/${name}.service"
            
            cat > "${service_file}" << EOF
[Unit]
Description=${description}
After=network.target

[Service]
Type=simple
ExecStart=${exec_start}
EOF
            
            if [[ "${exec_reload}" != "null" ]]; then
                echo "ExecReload=${exec_reload}" >> "${service_file}"
            fi
            
            if [[ "${restart}" != "null" ]]; then
                echo "Restart=${restart}" >> "${service_file}"
            fi
            
            if [[ "${user}" != "null" ]]; then
                echo "User=${user}" >> "${service_file}"
            fi
            
            if [[ "${group}" != "null" ]]; then
                echo "Group=${group}" >> "${service_file}"
            fi
            
            cat >> "${service_file}" << EOF

[Install]
WantedBy=multi-user.target
EOF
            
            systemctl daemon-reload
            systemctl enable "${name}"
            log "INFO" "커스텀 서비스 생성: ${name}"
        fi
    done
    
    log "INFO" "서비스 설정 완료"
}

# 부트로더 설정
setup_bootloader() {
    log "INFO" "부트로더 설정 중..."
    
    local bootloader_type=$(yq eval '.bootloader.type' "${CONFIG_FILE}")
    local timeout=$(yq eval '.bootloader.timeout' "${CONFIG_FILE}")
    
    if [[ "${bootloader_type}" == "grub" ]]; then
        # GRUB 설정
        if [[ "${timeout}" != "null" ]]; then
            sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${timeout}/" /etc/default/grub
        fi
        
        # GRUB 설정 업데이트
        grub-mkconfig -o /boot/grub/grub.cfg
        log "INFO" "GRUB 설정 완료"
    fi
    
    log "INFO" "부트로더 설정 완료"
}

# 로케일 설정
setup_locale() {
    log "INFO" "로케일 설정 중..."
    
    local locale=$(yq eval '.system.locale' "${CONFIG_FILE}")
    local timezone=$(yq eval '.system.timezone' "${CONFIG_FILE}")
    local keyboard_layout=$(yq eval '.system.keyboard_layout' "${CONFIG_FILE}")
    
    # 로케일 설정
    if [[ "${locale}" != "null" ]]; then
        sed -i "s/^#${locale}/${locale}/" /etc/locale.gen
        locale-gen
        echo "LANG=${locale}" > /etc/locale.conf
        log "INFO" "로케일 설정: ${locale}"
    fi
    
    # 타임존 설정
    if [[ "${timezone}" != "null" ]]; then
        ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
        log "INFO" "타임존 설정: ${timezone}"
    fi
    
    # 키보드 레이아웃 설정
    if [[ "${keyboard_layout}" != "null" ]]; then
        echo "KEYMAP=${keyboard_layout}" > /etc/vconsole.conf
        log "INFO" "키보드 레이아웃 설정: ${keyboard_layout}"
    fi
    
    log "INFO" "로케일 설정 완료"
}

# 방화벽 설정
setup_firewall() {
    log "INFO" "방화벽 설정 중..."
    
    local firewall_enabled=$(yq eval '.network.firewall.enabled' "${CONFIG_FILE}")
    
    if [[ "${firewall_enabled}" == "true" ]]; then
        # UFW 설치 및 설정
        if command -v ufw >/dev/null 2>&1; then
            local default_policy=$(yq eval '.network.firewall.default_policy' "${CONFIG_FILE}")
            
            # 기본 정책 설정
            ufw --force reset
            ufw default "${default_policy}"
            
            # 규칙 추가
            local rules_count=$(yq eval '.network.firewall.rules | length' "${CONFIG_FILE}")
            for ((i=0; i<rules_count; i++)); do
                local action=$(yq eval ".network.firewall.rules[${i}].action" "${CONFIG_FILE}")
                local protocol=$(yq eval ".network.firewall.rules[${i}].protocol" "${CONFIG_FILE}")
                local port=$(yq eval ".network.firewall.rules[${i}].port" "${CONFIG_FILE}")
                local source=$(yq eval ".network.firewall.rules[${i}].source" "${CONFIG_FILE}")
                
                if [[ "${action}" != "null" && "${protocol}" != "null" && "${port}" != "null" ]]; then
                    if [[ "${source}" == "any" ]]; then
                        ufw allow "${port}/${protocol}"
                    else
                        ufw allow from "${source}" to any port "${port}" proto "${protocol}"
                    fi
                    log "INFO" "방화벽 규칙 추가: ${action} ${port}/${protocol}"
                fi
            done
            
            # UFW 활성화
            ufw --force enable
            log "INFO" "방화벽 활성화 완료"
        fi
    fi
    
    log "INFO" "방화벽 설정 완료"
}

# 성능 튜닝
setup_performance() {
    log "INFO" "성능 튜닝 중..."
    
    # CPU 거버너 설정
    local cpu_governor=$(yq eval '.performance.cpu.governor' "${CONFIG_FILE}")
    if [[ "${cpu_governor}" != "null" ]]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            if [[ -f "${cpu}" ]]; then
                echo "${cpu_governor}" > "${cpu}"
            fi
        done
        log "INFO" "CPU 거버너 설정: ${cpu_governor}"
    fi
    
    # 메모리 튜닝
    local swappiness=$(yq eval '.performance.memory.swappiness' "${CONFIG_FILE}")
    if [[ "${swappiness}" != "null" ]]; then
        echo "${swappiness}" > /proc/sys/vm/swappiness
        echo "vm.swappiness=${swappiness}" >> /etc/sysctl.conf
        log "INFO" "Swappiness 설정: ${swappiness}"
    fi
    
    # 네트워크 튜닝
    local tcp_congestion=$(yq eval '.performance.network.tcp_congestion_control' "${CONFIG_FILE}")
    if [[ "${tcp_congestion}" != "null" ]]; then
        echo "${tcp_congestion}" > /proc/sys/net/ipv4/tcp_congestion_control
        echo "net.ipv4.tcp_congestion_control=${tcp_congestion}" >> /etc/sysctl.conf
        log "INFO" "TCP 혼잡 제어 설정: ${tcp_congestion}"
    fi
    
    # sysctl 적용
    sysctl -p
    
    log "INFO" "성능 튜닝 완료"
}

# 로깅 설정
setup_logging() {
    log "INFO" "로깅 설정 중..."
    
    # journald 설정
    local journald_storage=$(yq eval '.logging.journald.storage' "${CONFIG_FILE}")
    if [[ "${journald_storage}" != "null" ]]; then
        sed -i "s/^#Storage=auto/Storage=${journald_storage}/" /etc/systemd/journald.conf
    fi
    
    # logrotate 설정
    local logrotate_enabled=$(yq eval '.logging.logrotate.enabled' "${CONFIG_FILE}")
    if [[ "${logrotate_enabled}" == "true" ]]; then
        systemctl enable logrotate.timer
        systemctl start logrotate.timer
        log "INFO" "logrotate 활성화 완료"
    fi
    
    log "INFO" "로깅 설정 완료"
}

# 보안 설정
setup_security() {
    log "INFO" "보안 설정 중..."
    
    # AppArmor 설정
    local apparmor_enabled=$(yq eval '.security.apparmor.enabled' "${CONFIG_FILE}")
    if [[ "${apparmor_enabled}" == "true" ]]; then
        systemctl enable apparmor
        systemctl start apparmor
        log "INFO" "AppArmor 활성화 완료"
    fi
    
    # fail2ban 설정
    local fail2ban_enabled=$(yq eval '.security.fail2ban.enabled' "${CONFIG_FILE}")
    if [[ "${fail2ban_enabled}" == "true" ]]; then
        systemctl enable fail2ban
        systemctl start fail2ban
        log "INFO" "fail2ban 활성화 완료"
    fi
    
    # 커널 보안 설정
    local randomize_va_space=$(yq eval '.security.kernel_security.randomize_va_space' "${CONFIG_FILE}")
    if [[ "${randomize_va_space}" != "null" ]]; then
        echo "${randomize_va_space}" > /proc/sys/kernel/randomize_va_space
        echo "kernel.randomize_va_space=${randomize_va_space}" >> /etc/sysctl.conf
    fi
    
    log "INFO" "보안 설정 완료"
}

# 시스템 업데이트
update_system() {
    log "INFO" "시스템 업데이트 중..."
    
    # 패키지 목록 업데이트
    if command -v apt >/dev/null 2>&1; then
        apt update && apt upgrade -y
    elif command -v dnf >/dev/null 2>&1; then
        dnf update -y
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Syu --noconfirm
    fi
    
    log "INFO" "시스템 업데이트 완료"
}

# 설정 검증
verify_setup() {
    log "INFO" "설정 검증 중..."
    
    # 네트워크 연결 확인
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log "INFO" "네트워크 연결: 정상"
    else
        log "WARN" "네트워크 연결: 문제 있음"
    fi
    
    # 서비스 상태 확인
    local enabled_services=$(yq eval '.services.enabled | join(" ")' "${CONFIG_FILE}")
    for service in ${enabled_services}; do
        if systemctl is-active --quiet "${service}"; then
            log "INFO" "서비스 ${service}: 실행 중"
        else
            log "WARN" "서비스 ${service}: 실행되지 않음"
        fi
    done
    
    # 디스크 공간 확인
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ ${disk_usage} -lt 80 ]]; then
        log "INFO" "디스크 사용량: ${disk_usage}% (정상)"
    else
        log "WARN" "디스크 사용량: ${disk_usage}% (높음)"
    fi
    
    log "INFO" "설정 검증 완료"
}

# 메인 함수
main() {
    log "INFO" "Massive OS 시스템 설정 시작"
    
    check_root
    show_system_info
    check_config
    
    # 시스템 업데이트
    update_system
    
    # 설정 단계 실행
    setup_locale
    setup_network
    setup_storage
    setup_users
    setup_services
    setup_bootloader
    setup_firewall
    setup_performance
    setup_logging
    setup_security
    
    # 설정 검증
    verify_setup
    
    log "INFO" "Massive OS 시스템 설정 완료"
    log "INFO" "시스템을 재부팅하여 모든 변경사항을 적용하세요."
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
