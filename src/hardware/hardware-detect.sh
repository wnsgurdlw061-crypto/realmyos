#!/bin/bash
#
# UnifiedArch OS Hardware Detection System
# 하드웨어 자동 감지 및 드라이버 관리
#
# 기능:
# - GPU, Wi-Fi, 블루투스 등 하드웨어 자동 감지
# - 드라이버 자동 설치
# - 하드웨어 호환성 검사
# - 펌웨어 업데이트
#

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
HARDWARE_DB="/var/lib/unifiedarch/hardware.db"
DRIVER_CACHE="/var/cache/unifiedarch/drivers"
LOG_FILE="/var/log/unifiedarch-hardware.log"

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
log_hardware() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
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
    mkdir -p "$(dirname "$HARDWARE_DB")"
    mkdir -p "$DRIVER_CACHE"
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# GPU 감지
detect_gpu() {
    log_step "GPU 감지 중..."
    
    local gpu_info=()
    local gpu_count=0
    
    # PCI GPU 감지
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9a-f:.]{4}:[0-9a-f:.]{2}\.[0-9a-f]\.[0-9a-f]\ (VGA|3D|Display) ]]; then
            local vendor=$(echo "$line" | grep -o '\[.*\]' | tr -d '[]')
            local device=$(echo "$line" | grep -o 'VGA.*' | cut -d: -f2- | xargs)
            local class=$(echo "$line" | grep -o 'Class.*' | cut -d: -f2- | xargs)
            
            gpu_info[gpu_count]="$vendor:$device:$class"
            gpu_count=$((gpu_count + 1))
            
            log_hardware "GPU 감지: $vendor $device ($class)"
        fi
    done < <(lspci -v)
    
    # NVIDIA GPU 감지
    if command -v nvidia-smi &>/dev/null; then
        local nvidia_info=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -n1)
        if [[ -n "$nvidia_info" ]]; then
            local gpu_name=$(echo "$nvidia_info" | cut -d, -f1)
            local driver_version=$(echo "$nvidia_info" | cut -d, -f2)
            gpu_info[gpu_count]="NVIDIA:$gpu_name:Driver:$driver_version"
            gpu_count=$((gpu_count + 1))
            log_hardware "NVIDIA GPU 감지: $gpu_name (Driver: $driver_version)"
        fi
    fi
    
    # AMD GPU 감지
    if command -v amd GPUsinfo &>/dev/null; then
        local amd_info=$(amdgpu-pro --list 2>/dev/null | grep -A2 "GPU" | tail -n1)
        if [[ -n "$amd_info" ]]; then
            gpu_info[gpu_count]="AMD:$amd_info"
            gpu_count=$((gpu_count + 1))
            log_hardware "AMD GPU 감지: $amd_info"
        fi
    fi
    
    # Intel GPU 감지
    if [[ -d "/sys/class/drm" ]]; then
        for card in /sys/class/drm/card*; do
            if [[ -e "$card/device/vendor" ]]; then
                local vendor_hex=$(cat "$card/device/vendor" 2>/dev/null || echo "")
                local device_hex=$(cat "$card/device/device" 2>/dev/null || echo "")
                
                if [[ -n "$vendor_hex" && -n "$device_hex" ]]; then
                    local vendor=$(printf "0x%04x" "$((vendor_hex))" | xargs)
                    local device=$(printf "0x%04x" "$((device_hex))" | xargs)
                    
                    if [[ "$vendor" == "0x8086" ]]; then  # Intel
                        gpu_info[gpu_count]="Intel:$device"
                        gpu_count=$((gpu_count + 1))
                        log_hardware "Intel GPU 감지: $device"
                    fi
                fi
            fi
        done
    fi
    
    echo "${gpu_info[@]}"
    log_success "GPU 감지 완료: $gpu_count개 발견"
}

# 네트워크 장치 감지
detect_network() {
    log_step "네트워크 장치 감지 중..."
    
    local network_info=()
    local network_count=0
    
    # 이더넷 감지
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9a-f:.]{4}:[0-9a-f:.]{2}\.[0-9a-f]\.[0-9a-f]\ (Ethernet) ]]; then
            local interface=$(echo "$line" | grep -o 'eth[0-9]*' | head -n1)
            local vendor=$(echo "$line" | grep -o '\[.*\]' | tr -d '[]')
            local device=$(echo "$line" | grep -o 'Ethernet.*' | cut -d: -f2- | xargs)
            
            network_info[network_count]="Ethernet:$interface:$vendor:$device"
            network_count=$((network_count + 1))
            
            log_hardware "이더넷 감지: $interface ($vendor $device)"
        fi
    done < <(lspci -v)
    
    # 무선 네트워크 감지
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9a-f:.]{4}:[0-9a-f:.]{2}\.[0-9a-f]\.[0-9a-f]\ (Network) ]]; then
            local interface=$(echo "$line" | grep -o 'wlan[0-9]*' | head -n1)
            local vendor=$(echo "$line" | grep -o '\[.*\]' | tr -d '[]')
            local device=$(echo "$line" | grep -o 'Network.*' | cut -d: -f2- | xargs)
            
            network_info[network_count]="Wireless:$interface:$vendor:$device"
            network_count=$((network_count + 1))
            
            log_hardware "무선 네트워크 감지: $interface ($vendor $device)"
        fi
    done < <(lspci -v)
    
    # USB 네트워크 장치 감지
    while IFS= read -r line; do
        if [[ "$line" =~ (Ethernet|Network) ]]; then
            local vendor=$(echo "$line" | grep -o 'ID_VENDOR.*=' | cut -d= -f2)
            local device=$(echo "$line" | grep -o 'ID_MODEL.*=' | cut -d= -f2)
            local interface=$(echo "$line" | grep -o 'net[0-9]*' | head -n1)
            
            if [[ -n "$vendor" && -n "$device" ]]; then
                network_info[network_count]="USB:$interface:$vendor:$device"
                network_count=$((network_count + 1))
                
                log_hardware "USB 네트워크 감지: $interface ($vendor $device)"
            fi
        fi
    done < <(lsusb -v 2>/dev/null)
    
    echo "${network_info[@]}"
    log_success "네트워크 장치 감지 완료: $network_count개 발견"
}

# 오디오 장치 감지
detect_audio() {
    log_step "오디오 장치 감지 중..."
    
    local audio_info=()
    local audio_count=0
    
    # PCI 오디오 감지
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9a-f:.]{4}:[0-9a-f:.]{2}\.[0-9a-f]\.[0-9a-f]\ (Multimedia\ audio) ]]; then
            local vendor=$(echo "$line" | grep -o '\[.*\]' | tr -d '[]')
            local device=$(echo "$line" | grep -o 'Multimedia.*' | cut -d: -f2- | xargs)
            
            audio_info[audio_count]="PCI:$vendor:$device"
            audio_count=$((audio_count + 1))
            
            log_hardware "PCI 오디오 감지: $vendor $device"
        fi
    done < <(lspci -v)
    
    # USB 오디오 감지
    while IFS= read -r line; do
        if [[ "$line" =~ (Audio|Speaker|Microphone) ]]; then
            local vendor=$(echo "$line" | grep -o 'ID_VENDOR.*=' | cut -d= -f2)
            local device=$(echo "$line" | grep -o 'ID_MODEL.*=' | cut -d= -f2)
            
            if [[ -n "$vendor" && -n "$device" ]]; then
                audio_info[audio_count]="USB:$vendor:$device"
                audio_count=$((audio_count + 1))
                
                log_hardware "USB 오디오 감지: $vendor $device"
            fi
        fi
    done < <(lsusb -v 2>/dev/null)
    
    # ALSA 장치 감지
    if [[ -d "/proc/asound" ]]; then
        for card in /proc/asound/card*; do
            if [[ -f "$card/id" ]]; then
                local card_name=$(cat "$card/id" 2>/dev/null || echo "Unknown")
                audio_info[audio_count]="ALSA:$card_name"
                audio_count=$((audio_count + 1))
                
                log_hardware "ALSA 카드 감지: $card_name"
            fi
        done
    fi
    
    echo "${audio_info[@]}"
    log_success "오디오 장치 감지 완료: $audio_count개 발견"
}

# 블루투스 감지
detect_bluetooth() {
    log_step "블루투스 감지 중..."
    
    local bluetooth_info=()
    local bluetooth_count=0
    
    # 블루투스 어댑터 감지
    if command -v hciconfig &>/dev/null; then
        local adapters=$(hciconfig 2>/dev/null | grep -o 'hci[0-9]*' | sort -u)
        for adapter in $adapters; do
            local adapter_info=$(hciconfig "$adapter" 2>/dev/null | grep -A5 "$adapter" | head -n6)
            local mac=$(echo "$adapter_info" | grep -o 'BD Address:.*' | cut -d: -f2- | xargs)
            local type=$(echo "$adapter_info" | grep -o 'Type:.*' | cut -d: -f2- | xargs)
            
            bluetooth_info[bluetooth_count]="Adapter:$adapter:$type:$mac"
            bluetooth_count=$((bluetooth_count + 1))
            
            log_hardware "블루투스 어댑터 감지: $adapter ($type, $mac)"
        done
    fi
    
    # USB 블루투스 감지
    while IFS= read -r line; do
        if [[ "$line" =~ (Bluetooth|Wireless) ]]; then
            local vendor=$(echo "$line" | grep -o 'ID_VENDOR.*=' | cut -d= -f2)
            local device=$(echo "$line" | grep -o 'ID_MODEL.*=' | cut -d= -f2)
            
            if [[ -n "$vendor" && -n "$device" ]]; then
                bluetooth_info[bluetooth_count]="USB:$vendor:$device"
                bluetooth_count=$((bluetooth_count + 1))
                
                log_hardware "USB 블루투스 감지: $vendor $device"
            fi
        fi
    done < <(lsusb -v 2>/dev/null)
    
    echo "${bluetooth_info[@]}"
    log_success "블루투스 감지 완료: $bluetooth_count개 발견"
}

# 입력 장치 감지
detect_input() {
    log_step "입력 장치 감지 중..."
    
    local input_info=()
    local input_count=0
    
    # 키보드 감지
    if [[ -d "/dev/input" ]]; then
        for device in /dev/input/event*; do
            if [[ -c "$device" ]]; then
                local device_name=$(udevadm info --query=property --name="$device" 2>/dev/null | grep ID_INPUT_KEYBOARD | wc -l)
                if [[ $device_name -gt 0 ]]; then
                    local keyboard_name=$(udevadm info --query=property --name="$device" 2>/dev/null | grep ID_MODEL | cut -d= -f2 | tr -d '"')
                    
                    input_info[input_count]="Keyboard:$keyboard_name"
                    input_count=$((input_count + 1))
                    
                    log_hardware "키보드 감지: $keyboard_name"
                fi
            fi
        done
    fi
    
    # 마우스 감지
    for device in /dev/input/mouse* /dev/input/event*; do
        if [[ -c "$device" ]]; then
            local device_name=$(udevadm info --query=property --name="$device" 2>/dev/null | grep ID_INPUT_MOUSE | wc -l)
            if [[ $device_name -gt 0 ]]; then
                local mouse_name=$(udevadm info --query=property --name="$device" 2>/dev/null | grep ID_MODEL | cut -d= -f2 | tr -d '"')
                
                input_info[input_count]="Mouse:$mouse_name"
                input_count=$((input_count + 1))
                
                log_hardware "마우스 감지: $mouse_name"
            fi
        fi
    done
    
    # 터치패드 감지
    for device in /dev/input/event*; do
        if [[ -c "$device" ]]; then
            local device_name=$(udevadm info --query=property --name="$device" 2>/dev/null | grep ID_INPUT_TOUCHPAD | wc -l)
            if [[ $device_name -gt 0 ]]; then
                local touchpad_name=$(udevadm info --query=property --name="$device" 2>/dev/null | grep ID_MODEL | cut -d= -f2 | tr -d '"')
                
                input_info[input_count]="Touchpad:$touchpad_name"
                input_count=$((input_count + 1))
                
                log_hardware "터치패드 감지: $touchpad_name"
            fi
        fi
    done
    
    echo "${input_info[@]}"
    log_success "입력 장치 감지 완료: $input_count개 발견"
}

# 저장 장치 감지
detect_storage() {
    log_step "저장 장치 감지 중..."
    
    local storage_info=()
    local storage_count=0
    
    # 하드디스크 감지
    lsblk -d -o NAME,SIZE,TYPE,MODEL,VENDOR | while read -r line; do
        if [[ -n "$line" ]]; then
            local name=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $2}')
            local type=$(echo "$line" | awk '{print $3}')
            local model=$(echo "$line" | awk '{print $4}')
            local vendor=$(echo "$line" | awk '{print $5}')
            
            storage_info[storage_count]="Disk:$name:$size:$type:$model:$vendor"
            storage_count=$((storage_count + 1))
            
            log_hardware "디스크 감지: $name ($size, $type, $model, $vendor)"
        fi
    done
    
    # SSD 감지
    if command -v smartctl &>/dev/null; then
        for device in /dev/sd[a-z]; do
            if [[ -b "$device" ]]; then
                local smart_info=$(smartctl -i "$device" 2>/dev/null | grep -E "(Model:|Device Model:)")
                if [[ -n "$smart_info" ]]; then
                    local model=$(echo "$smart_info" | cut -d: -f2- | xargs)
                    local device_name=$(basename "$device")
                    
                    storage_info[storage_count]="SSD:$device_name:$model"
                    storage_count=$((storage_count + 1))
                    
                    log_hardware "SSD 감지: $device_name ($model)"
                fi
            fi
        done
    fi
    
    echo "${storage_info[@]}"
    log_success "저장 장치 감지 완료: $storage_count개 발견"
}

# 드라이버 데이터베이스 구축
build_driver_database() {
    log_step "드라이버 데이터베이스 구축 중..."
    
    # GPU 드라이버 매핑
    cat > "$DRIVER_CACHE/gpu-drivers.db" << 'EOF'
# GPU 드라이버 매핑 데이터베이스

# NVIDIA 드라이버
nvidia_10xx=nvidia-470xx-dkms
nvidia_20xx=nvidia-510xx-dkms
nvidia_30xx=nvidia-515xx-dkms
nvidia_40xx=nvidia-525xx-dkms

# AMD 드라이버
amd_rx_5000=amdgpu-pro
amd_rx_6000=amdgpu-pro
amd_rx_7000=amdgpu

# Intel 드라이버
intel_gen8=intel-media-driver
intel_gen9=intel-media-driver
intel_gen11=intel-media-driver
intel_gen12=intel-media-driver

# 범용 드라이버
generic_nouveau=nouveau
generic_amdgpu=amdgpu
generic_intel=intel
EOF
    
    # 네트워크 드라이버 매핑
    cat > "$DRIVER_CACHE/network-drivers.db" << 'EOF'
# 네트워크 드라이버 매핑 데이터베이스

# 이더넷 드라이버
intel_e1000e=e1000e
intel_igb=igb
intel_ixgbe=ixgbe
realtek_r8168=r8168
broadcom_tg3=tg3

# 무선 드라이버
intel_iwlwifi=iwlwifi
intel_iwlmvm=iwlmvm
broadcom_brcmfmac=brcmfmac
realtek_rtl8723be=rtl8723be
mediatek_mt76=mt76
ath_ath10k=ath10k-pci

# 범용 드라이버
generic_ethernet=ethernet
generic_wireless=wireless
EOF
    
    # 오디오 드라이버 매핑
    cat > "$DRIVER_CACHE/audio-drivers.db" << 'EOF'
# 오디오 드라이버 매핑 데이터베이스

# Intel 오디오
intel_hda=snd-hda-intel
intel_sof=sof-firmware

# AMD 오디오
amd_acp=snd-acp-pch
amd_ati=snd-hda-amd

# 범용 오디오
generic_hda=snd-hda-generic
generic_usb=usb-audio
EOF
    
    log_success "드라이버 데이터베이스 구축 완료"
}

# 드라이버 자동 설치
install_drivers() {
    log_step "드라이버 자동 설치 중..."
    
    # GPU 드라이버 설치
    local gpu_info=($(detect_gpu))
    for gpu in "${gpu_info[@]}"; do
        local vendor=$(echo "$gpu" | cut -d: -f1)
        
        case "$vendor" in
            NVIDIA)
                log_info "NVIDIA 드라이버 설치 중..."
                pacman -S --needed nvidia-dkms nvidia-utils nvidia-settings 2>/dev/null || log_warning "NVIDIA 드라이버 설치 실패"
                ;;
            AMD)
                log_info "AMD 드라이버 설치 중..."
                pacman -S --needed amdgpu-pro 2>/dev/null || log_warning "AMD 드라이버 설치 실패"
                ;;
            Intel)
                log_info "Intel 드라이버 설치 중..."
                pacman -S --needed intel-media-driver 2>/dev/null || log_warning "Intel 드라이버 설치 실패"
                ;;
        esac
    done
    
    # 네트워크 드라이버 설치
    local network_info=($(detect_network))
    for network in "${network_info[@]}"; do
        local type=$(echo "$network" | cut -d: -f1)
        
        if [[ "$type" == "Wireless" ]]; then
            log_info "무선 네트워크 드라이버 설치 중..."
            pacman -S --needed wireless_tools wpa_supplicant networkmanager 2>/dev/null || log_warning "무선 드라이버 설치 실패"
        fi
    done
    
    # 오디오 드라이버 설치
    local audio_info=($(detect_audio))
    if [[ ${#audio_info[@]} -gt 0 ]]; then
        log_info "오디오 드라이버 설치 중..."
        pacman -S --needed alsa-utils pulseaudio pipewire pipewire-pulse 2>/dev/null || log_warning "오디오 드라이버 설치 실패"
    fi
    
    # 블루투스 드라이버 설치
    local bluetooth_info=($(detect_bluetooth))
    if [[ ${#bluetooth_info[@]} -gt 0 ]]; then
        log_info "블루투스 드라이버 설치 중..."
        pacman -S --needed bluez bluez-utils 2>/dev/null || log_warning "블루투스 드라이버 설치 실패"
    fi
    
    log_success "드라이버 자동 설치 완료"
}

# 하드웨어 호환성 검사
check_compatibility() {
    log_step "하드웨어 호환성 검사 중..."
    
    local compatibility_issues=()
    local issue_count=0
    
    # GPU 호환성 검사
    local gpu_info=($(detect_gpu))
    for gpu in "${gpu_info[@]}"; do
        local vendor=$(echo "$gpu" | cut -d: -f1)
        
        # NVIDIA 최신 커널 호환성
        if [[ "$vendor" == "NVIDIA" ]]; then
            local kernel_version=$(uname -r)
            local major_version=$(echo "$kernel_version" | cut -d. -f1)
            
            if [[ $major_version -ge 6 ]]; then
                compatibility_issues[issue_count]="NVIDIA:커널 6.x에서 일부 기능 제한"
                issue_count=$((issue_count + 1))
                log_hardware "호환성 문제: NVIDIA + 커널 6.x"
            fi
        fi
    done
    
    # Wi-Fi 호환성 검사
    local network_info=($(detect_network))
    for network in "${network_info[@]}"; do
        local type=$(echo "$network" | cut -d: -f1)
        
        if [[ "$type" == "Wireless" ]]; then
            # 펌웨어 확인
            local firmware_check=$(ls /usr/lib/firmware/ | grep -c "iwlwifi\|ath10k\|brcm" || echo "0")
            if [[ $firmware_check -eq 0 ]]; then
                compatibility_issues[issue_count]="WiFi:필요한 펌웨어 없음"
                issue_count=$((issue_count + 1))
                log_hardware "호환성 문제: WiFi 펌웨어 부족"
            fi
        fi
    done
    
    # 메모리 요구사항 검사
    local total_memory=$(free -m | grep '^Mem:' | awk '{print $2}')
    if [[ $total_memory -lt 2048 ]]; then
        compatibility_issues[issue_count]="Memory:2GB 미만 - 일부 기능 제한"
        issue_count=$((issue_count + 1))
        log_hardware "호환성 문제: 메모리 부족"
    fi
    
    # 디스크 공간 검사
    local root_space=$(df -BG / | tail -n1 | awk '{print $4}')
    if [[ $root_space -lt 10240 ]]; then  # 10GB 미만
        compatibility_issues[issue_count]="Disk:10GB 미만 - 설치 권장"
        issue_count=$((issue_count + 1))
        log_hardware "호환성 문제: 디스크 공간 부족"
    fi
    
    echo "${compatibility_issues[@]}"
    
    if [[ $issue_count -eq 0 ]]; then
        log_success "하드웨어 호환성 검사 통과"
    else
        log_warning "하드웨어 호환성 문제 발견: $issue_count개"
    fi
}

# 하드웨어 정보 보고
report_hardware() {
    log_step "하드웨어 정보 보고 생성 중..."
    
    local report_file="/var/log/unifiedarch-hardware-report.txt"
    
    cat > "$report_file" << EOF
========================================
     UnifiedArch OS 하드웨어 정보 보고
 생성 시간: $(date '+%Y-%m-%d %H:%M:%S')
 커널 버전: $(uname -r)
 아키텍처: $(uname -m)
========================================

[시스템 정보]
CPU: $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)
코어 수: $(grep -c '^processor' /proc/cpuinfo)
메모리: $(free -h | grep '^Mem:' | awk '{print $2}')
스왑: $(free -h | grep '^Swap:' | awk '{print $2}')

[GPU 정보]
EOF
    
    local gpu_info=($(detect_gpu))
    for i in "${!gpu_info[@]}"; do
        echo "GPU $((i+1)): ${gpu_info[i]}" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

[네트워크 정보]
EOF
    
    local network_info=($(detect_network))
    for i in "${!network_info[@]}"; do
        echo "네트워크 $((i+1)): ${network_info[i]}" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

[오디오 정보]
EOF
    
    local audio_info=($(detect_audio))
    for i in "${!audio_info[@]}"; do
        echo "오디오 $((i+1)): ${audio_info[i]}" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

[블루투스 정보]
EOF
    
    local bluetooth_info=($(detect_bluetooth))
    for i in "${!bluetooth_info[@]}"; do
        echo "블루투스 $((i+1)): ${bluetooth_info[i]}" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

[입력 장치 정보]
EOF
    
    local input_info=($(detect_input))
    for i in "${!input_info[@]}"; do
        echo "입력 $((i+1)): ${input_info[i]}" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

[저장 장치 정보]
EOF
    
    local storage_info=($(detect_storage))
    for i in "${!storage_info[@]}"; do
        echo "저장 $((i+1)): ${storage_info[i]}" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

[호환성 검사]
EOF
    
    local compatibility_issues=($(check_compatibility))
    if [[ ${#compatibility_issues[@]} -gt 0 ]]; then
        for i in "${!compatibility_issues[@]}"; do
            echo "문제 $((i+1)): ${compatibility_issues[i]}" >> "$report_file"
        done
    else
        echo "호환성: 양호" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

========================================
EOF
    
    log_success "하드웨어 정보 보고 완료: $report_file"
}

# 하드웨어 모니터링 시작
start_monitoring() {
    log_step "하드웨어 모니터링 시작 중..."
    
    # udev 모니터링 시작
    mkdir -p /run/unifiedarch/hardware-monitor
    
    cat > /run/unifiedarch/hardware-monitor/hardware-monitor.sh << 'EOF'
#!/bin/bash
# 하드웨어 변경 모니터링 스크립트

LOG_FILE="/var/log/unifiedarch-hardware-monitor.log"

log_hardware() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

udevadm monitor --property --udev 2>&1 | while read -r line; do
    if [[ "$line" =~ (add|remove|change) ]]; then
        log_hardware "하드웨어 변경: $line"
    fi
done
EOF
    
    chmod +x /run/unifiedarch/hardware-monitor/hardware-monitor.sh
    
    # systemd 서비스 생성
    cat > /etc/systemd/system/unifiedarch-hardware-monitor.service << 'EOF'
[Unit]
Description=UnifiedArch OS Hardware Monitor
After=systemd-udevd.service

[Service]
Type=simple
ExecStart=/run/unifiedarch/hardware-monitor/hardware-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable unifiedarch-hardware-monitor.service
    systemctl start unifiedarch-hardware-monitor.service
    
    log_success "하드웨어 모니터링 시작 완료"
}

# 도움말
show_help() {
    echo "UnifiedArch OS Hardware Detection System"
    echo ""
    echo "사용법: $0 [명령어] [인자]"
    echo ""
    echo "명령어:"
    echo "  detect-all          - 모든 하드웨어 감지"
    echo "  detect-gpu          - GPU 감지"
    echo "  detect-network      - 네트워크 감지"
    echo "  detect-audio        - 오디오 감지"
    echo "  detect-bluetooth    - 블루투스 감지"
    echo "  detect-input        - 입력 장치 감지"
    echo "  detect-storage      - 저장 장치 감지"
    echo "  install-drivers     - 드라이버 자동 설치"
    echo "  check-compatibility  - 호환성 검사"
    echo "  report              - 하드웨어 정보 보고"
    echo "  monitor             - 하드웨어 모니터링 시작"
    echo "  build-db            - 드라이버 데이터베이스 구축"
    echo "  help                - 이 도움말"
    echo ""
    echo "예시:"
    echo "  $0 detect-all"
    echo "  $0 install-drivers"
    echo "  $0 report"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    check_root
    create_directories
    
    case "$action" in
        detect-all)
            detect_gpu
            detect_network
            detect_audio
            detect_bluetooth
            detect_input
            detect_storage
            ;;
        detect-gpu)
            detect_gpu
            ;;
        detect-network)
            detect_network
            ;;
        detect-audio)
            detect_audio
            ;;
        detect-bluetooth)
            detect_bluetooth
            ;;
        detect-input)
            detect_input
            ;;
        detect-storage)
            detect_storage
            ;;
        install-drivers)
            build_driver_database
            install_drivers
            ;;
        check-compatibility)
            check_compatibility
            ;;
        report)
            report_hardware
            ;;
        monitor)
            start_monitoring
            ;;
        build-db)
            build_driver_database
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
