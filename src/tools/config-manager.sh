#!/bin/bash
# UnifiedArch OS 설정 관리 시스템
# 실제로 동작하는 YAML 기반 설정 관리 도구

set -euo pipefail

# 버전 정보
VERSION="1.0.0"

# 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_DIR="$PROJECT_ROOT/src/config"
SYSTEM_CONFIG_DIR="/etc/unifiedarch"
USER_CONFIG_DIR="$HOME/.config/unifiedarch"

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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 헬퍼 함수
banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 ____  _ _ _   _                     _      
| __ )(_) | | | | __ _ _ __   __ _ (_)_ __ 
|  _ \| | | |_| |/ _` | '_ \ / _` || | '_ \
| |_) | | |  _  | (_| | | | | (_| || | | | |
|____/|_|_|_| |_|\__,_|_| |_|\__,_||_|_| |_|
                                              
        설정 관리 시스템 v1.0
EOF
    echo -e "${NC}"
}

# YAML 파싱 함수 (간단한 구현)
yaml_get_value() {
    local file="$1"
    local key="$2"
    local default_value="${3:-}"
    
    if [[ ! -f "$file" ]]; then
        echo "$default_value"
        return 1
    fi
    
    # 간단한 YAML 파싱 (키: 값 형식)
    local value=$(grep "^$key:" "$file" | cut -d: -f2- | sed 's/^ *//' | sed 's/ *$//' | tr -d '"')
    
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default_value"
        return 1
    fi
}

# YAML 값 설정 함수
yaml_set_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    # 파일이 없으면 생성
    if [[ ! -f "$file" ]]; then
        mkdir -p "$(dirname "$file")"
        touch "$file"
    fi
    
    # 키가 이미 있으면 업데이트
    if grep -q "^$key:" "$file"; then
        sed -i "s/^$key:.*/$key: $value/" "$file"
    else
        # 새 키 추가
        echo "$key: $value" >> "$file"
    fi
}

# 설정 파일 백업
backup_config() {
    local config_file="$1"
    local backup_dir="$2"
    
    if [[ -f "$config_file" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$backup_dir/$(basename "$config_file").$timestamp"
        
        mkdir -p "$backup_dir"
        cp "$config_file" "$backup_file"
        log_success "설정 파일 백업됨: $backup_file"
    else
        log_warning "설정 파일 없음: $config_file"
    fi
}

# 설정 파일 복원
restore_config() {
    local config_file="$1"
    local backup_file="$2"
    
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$config_file"
        log_success "설정 파일 복원됨: $config_file"
    else
        log_error "백업 파일 없음: $backup_file"
        return 1
    fi
}

# 설정 파일 유효성 검사
validate_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "설정 파일 없음: $config_file"
        return 1
    fi
    
    # 기본 구조 검사
    local required_keys=("system" "version" "variant")
    
    for key in "${required_keys[@]}"; do
        if ! grep -q "^$key:" "$config_file"; then
            log_error "필수 키 없음: $key"
            return 1
        fi
    done
    
    # YAML 문법 기본 검사
    if python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
        log_success "설정 파일 유효성 검사 통과"
        return 0
    else
        log_error "설정 파일 YAML 문법 오류"
        return 1
    fi
}

# 설정 파일 병합
merge_configs() {
    local base_file="$1"
    local override_file="$2"
    local output_file="$3"
    
    if [[ ! -f "$base_file" ]]; then
        log_error "기본 설정 파일 없음: $base_file"
        return 1
    fi
    
    if [[ ! -f "$override_file" ]]; then
        log_warning "오버라이드 설정 파일 없음: $override_file"
        cp "$base_file" "$output_file"
        return 0
    fi
    
    # 기본 파일 복사
    cp "$base_file" "$output_file"
    
    # 오버라이드 파일의 키들을 출력 파일에 적용
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*(.*)[[:space:]]*$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            yaml_set_value "$output_file" "$key" "$value"
        fi
    done < "$override_file"
    
    log_success "설정 파일 병합 완료: $output_file"
}

# 설정 템플릿 생성
create_template() {
    local template_type="$1"
    local output_file="$2"
    
    case "$template_type" in
        "standard")
            cat > "$output_file" << 'EOF'
# UnifiedArch OS 설정 - Standard 변형
system:
  name: "UnifiedArch"
  version: "1.0.0"
  variant: "standard"
  
# 기본 설정
base:
  locale: "ko_KR.UTF-8"
  timezone: "Asia/Seoul"
  hostname: "unifiedarch"
  keyboard: "us"
  
# Init 시스템
init_system:
  type: "systemd"
  
# 커널
kernel:
  type: "linux"
  
# 데스크톱
desktop:
  type: "gnome"
  display_manager: "gdm"
  
# 보안
security:
  firewall_enabled: true
  auto_updates: true
  
# 성능
performance:
  profile: "balanced"
EOF
            ;;
        "minimal")
            cat > "$output_file" << 'EOF'
# UnifiedArch OS 설정 - Minimal 변형
system:
  name: "UnifiedArch"
  version: "1.0.0"
  variant: "minimal"
  
# 기본 설정
base:
  locale: "ko_KR.UTF-8"
  timezone: "Asia/Seoul"
  hostname: "unifiedarch"
  keyboard: "us"
  
# Init 시스템
init_system:
  type: "systemd"
  
# 커널
kernel:
  type: "linux"
  
# 데스크톱
desktop:
  type: "i3"
  
# 보안
security:
  firewall_enabled: true
  auto_updates: false
  
# 성능
performance:
  profile: "powersave"
EOF
            ;;
        "gaming")
            cat > "$output_file" << 'EOF'
# UnifiedArch OS 설정 - Gaming 변형
system:
  name: "UnifiedArch"
  version: "1.0.0"
  variant: "gaming"
  
# 기본 설정
base:
  locale: "ko_KR.UTF-8"
  timezone: "Asia/Seoul"
  hostname: "unifiedarch-gaming"
  keyboard: "us"
  
# Init 시스템
init_system:
  type: "systemd"
  
# 커널
kernel:
  type: "linux-zen"
  
# 데스크톱
desktop:
  type: "gnome"
  display_manager: "gdm"
  
# 보안
security:
  firewall_enabled: false
  auto_updates: false
  
# 성능
performance:
  profile: "performance"
  
# 게이밍
gaming:
  steam_enabled: true
  nvidia_drivers: true
  low_latency_kernel: true
EOF
            ;;
        *)
            log_error "알 수 없는 템플릿 타입: $template_type"
            return 1
            ;;
    esac
    
    log_success "템플릿 생성됨: $output_file"
}

# 설정 적용
apply_config() {
    local config_file="$1"
    local scope="${2:-system}"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "설정 파일 없음: $config_file"
        return 1
    fi
    
    log_step "설정 적용 중..."
    
    case "$scope" in
        "system")
            # 시스템 전역 설정 적용
            if [[ $EUID -eq 0 ]]; then
                # 시스템 설정 디렉토리 생성
                mkdir -p "$SYSTEM_CONFIG_DIR"
                
                # 설정 파일 복사
                cp "$config_file" "$SYSTEM_CONFIG_DIR/config.yaml"
                
                # 로케일 설정
                local locale=$(yaml_get_value "$config_file" "base.locale")
                if [[ -n "$locale" ]]; then
                    sed -i "s/^#*$locale/$locale/" /etc/locale.gen
                    locale-gen
                    echo "LANG=$locale" > /etc/locale.conf
                    log_success "로케일 설정됨: $locale"
                fi
                
                # 시간대 설정
                local timezone=$(yaml_get_value "$config_file" "base.timezone")
                if [[ -n "$timezone" ]]; then
                    ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
                    log_success "시간대 설정됨: $timezone"
                fi
                
                # 호스트 이름 설정
                local hostname=$(yaml_get_value "$config_file" "base.hostname")
                if [[ -n "$hostname" ]]; then
                    echo "$hostname" > /etc/hostname
                    # hosts 파일 업데이트
                    sed -i "s/127.0.1.1.*/127.0.1.1 $hostname.localdomain $hostname/" /etc/hosts
                    log_success "호스트 이름 설정됨: $hostname"
                fi
                
                log_success "시스템 설정 적용 완료"
            else
                log_error "시스템 설정 적용에는 루트 권한이 필요합니다"
                return 1
            fi
            ;;
            
        "user")
            # 사용자 설정 적용
            mkdir -p "$USER_CONFIG_DIR"
            cp "$config_file" "$USER_CONFIG_DIR/config.yaml"
            
            # 사용자별 설정 적용
            local desktop_type=$(yaml_get_value "$config_file" "desktop.type")
            if [[ -n "$desktop_type" ]]; then
                # 데스크톱 설정 적용 (예: GNOME)
                if command -v gsettings >/dev/null 2>&1; then
                    case "$desktop_type" in
                        "gnome")
                            gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
                            gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/gnome/adwaita-day.jpg'
                            ;;
                    esac
                    log_success "데스크톱 설정 적용됨: $desktop_type"
                fi
            fi
            
            log_success "사용자 설정 적용 완료"
            ;;
            
        *)
            log_error "알 수 없는 적용 범위: $scope"
            return 1
            ;;
    esac
}

# 설정 상태 확인
check_config_status() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "설정 파일 없음: $config_file"
        return 1
    fi
    
    echo "=== 설정 상태 ==="
    echo "파일: $config_file"
    echo "크기: $(du -h "$config_file" | cut -f1)"
    echo "수정 시간: $(stat -c %y "$config_file")"
    echo ""
    
    echo "=== 설정 내용 ==="
    
    # 주요 설정 값 표시
    local system_name=$(yaml_get_value "$config_file" "system.name")
    local version=$(yaml_get_value "$config_file" "system.version")
    local variant=$(yaml_get_value "$config_file" "system.variant")
    local locale=$(yaml_get_value "$config_file" "base.locale")
    local hostname=$(yaml_get_value "$config_file" "base.hostname")
    local desktop=$(yaml_get_value "$config_file" "desktop.type")
    
    echo "시스템 이름: $system_name"
    echo "버전: $version"
    echo "변형: $variant"
    echo "로케일: $locale"
    echo "호스트 이름: $hostname"
    echo "데스크톱: $desktop"
    echo ""
    
    # 현재 시스템 상태와 비교
    echo "=== 현재 시스템 상태 ==="
    echo "현재 로케일: ${LANG:-설정되지 않음}"
    echo "현재 호스트 이름: $(hostname)"
    echo "현재 시간대: $(timedatectl show -p Timezone --value 2>/dev/null || echo '알 수 없음')"
    echo "현재 데스크톱: ${XDG_CURRENT_DESKTOP:-설정되지 않음}"
}

# 설정 동기화
sync_configs() {
    local source_config="$1"
    local target_scope="${2:-all}"
    
    if [[ ! -f "$source_config" ]]; then
        log_error "소스 설정 파일 없음: $source_config"
        return 1
    fi
    
    log_step "설정 동기화 중..."
    
    case "$target_scope" in
        "all")
            # 시스템 설정 동기화
            if [[ $EUID -eq 0 ]]; then
                apply_config "$source_config" "system"
            else
                log_warning "루트 권한이 없어 시스템 설정 동기화 건너뜀"
            fi
            
            # 사용자 설정 동기화
            apply_config "$source_config" "user"
            ;;
            
        "system")
            apply_config "$source_config" "system"
            ;;
            
        "user")
            apply_config "$source_config" "user"
            ;;
            
        *)
            log_error "알 수 없는 동기화 범위: $target_scope"
            return 1
            ;;
    esac
    
    log_success "설정 동기화 완료"
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 설정 관리 시스템"
    echo ""
    echo "사용법: $0 <명령> [인자]"
    echo ""
    echo "명령:"
    echo "  get <file> <key>           - 설정 값 읽기"
    echo "  set <file> <key> <value>   - 설정 값 설정"
    echo "  backup <file> <dir>        - 설정 파일 백업"
    echo "  restore <file> <backup>    - 설정 파일 복원"
    echo "  validate <file>            - 설정 파일 유효성 검사"
    echo "  merge <base> <override> <output> - 설정 파일 병합"
    echo "  template <type> <output>   - 설정 템플릿 생성"
    echo "  apply <file> [scope]       - 설정 적용 (system/user)"
    echo "  status <file>              - 설정 상태 확인"
    echo "  sync <file> [scope]        - 설정 동기화"
    echo "  help                       - 이 도움말 표시"
    echo ""
    echo "템플릿 타입:"
    echo "  standard, minimal, gaming"
    echo ""
    echo "적용 범위:"
    echo "  system - 시스템 전역 설정 (루트 권한 필요)"
    echo "  user   - 사용자 설정"
    echo "  all    - 모든 설정"
}

# 메인 함수
main() {
    local command="${1:-help}"
    
    case "$command" in
        "get")
            if [[ $# -ne 3 ]]; then
                log_error "인자 부족: get <file> <key>"
                exit 1
            fi
            yaml_get_value "$2" "$3"
            ;;
        "set")
            if [[ $# -ne 4 ]]; then
                log_error "인자 부족: set <file> <key> <value>"
                exit 1
            fi
            yaml_set_value "$2" "$3" "$4"
            ;;
        "backup")
            if [[ $# -ne 3 ]]; then
                log_error "인자 부족: backup <file> <dir>"
                exit 1
            fi
            backup_config "$2" "$3"
            ;;
        "restore")
            if [[ $# -ne 3 ]]; then
                log_error "인자 부족: restore <file> <backup>"
                exit 1
            fi
            restore_config "$2" "$3"
            ;;
        "validate")
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: validate <file>"
                exit 1
            fi
            validate_config "$2"
            ;;
        "merge")
            if [[ $# -ne 4 ]]; then
                log_error "인자 부족: merge <base> <override> <output>"
                exit 1
            fi
            merge_configs "$2" "$3" "$4"
            ;;
        "template")
            if [[ $# -ne 3 ]]; then
                log_error "인자 부족: template <type> <output>"
                exit 1
            fi
            create_template "$2" "$3"
            ;;
        "apply")
            if [[ $# -lt 2 ]]; then
                log_error "인자 부족: apply <file> [scope]"
                exit 1
            fi
            apply_config "$2" "${3:-system}"
            ;;
        "status")
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: status <file>"
                exit 1
            fi
            check_config_status "$2"
            ;;
        "sync")
            if [[ $# -lt 2 ]]; then
                log_error "인자 부족: sync <file> [scope]"
                exit 1
            fi
            sync_configs "$2" "${3:-all}"
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
