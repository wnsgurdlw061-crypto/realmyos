#!/bin/bash
# UnifiedArch OS 패키지 관리 시스템
# 실제로 동작하는 Arch Linux 패키지 관리 확장 도구

set -euo pipefail

# 버전 정보
VERSION="1.0.0"

# 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PACKAGES_DIR="$PROJECT_ROOT/src/packages"
REPO_CACHE_DIR="/var/cache/unifiedarch/packages"
CONFIG_DIR="/etc/unifiedarch"

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
                                              
        패키지 관리 시스템 v1.0
EOF
    echo -e "${NC}"
}

# 루트 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "이 작업은 루트 권한이 필요합니다"
        exit 1
    fi
}

# 네트워크 연결 확인
check_network() {
    if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
        log_error "인터넷 연결이 필요합니다"
        exit 1
    fi
}

# 패키지 데이터베이스 업데이트
update_package_db() {
    log_step "패키지 데이터베이스 업데이트 중..."
    
    if pacman -Sy; then
        log_success "패키지 데이터베이스 업데이트 완료"
    else
        log_error "패키지 데이터베이스 업데이트 실패"
        return 1
    fi
}

# 저장소 관리
manage_repositories() {
    local action="$1"
    local repo_name="$2"
    
    local pacman_conf="/etc/pacman.conf"
    
    case "$action" in
        "enable")
            if grep -q "^\[$repo_name\]" "$pacman_conf"; then
                # 이미 존재하면 활성화
                sed -i "s/^\[$repo_name\]$/#&/" "$pacman_conf"
                sed -i "s/^# \[$repo_name\]$/[$repo_name]/" "$pacman_conf"
                sed -i "/^\[$repo_name\]/,/^\[/ s/^#//g" "$pacman_conf"
                log_success "저장소 활성화: $repo_name"
            else
                log_warning "저장소 없음: $repo_name"
            fi
            ;;
            
        "disable")
            if grep -q "^\[$repo_name\]" "$pacman_conf"; then
                sed -i "s/^\[$repo_name\]/#&/" "$pacman_conf"
                sed -i "/^\[$repo_name\]/,/^\[/ s/^/#/" "$pacman_conf"
                log_success "저장소 비활성화: $repo_name"
            else
                log_warning "저장소 없음: $repo_name"
            fi
            ;;
            
        "add")
            if ! grep -q "^\[$repo_name\]" "$pacman_conf"; then
                cat >> "$pacman_conf" << EOF

[$repo_name]
SigLevel = Optional TrustAll
Server = https://unifiedarch.org/repo/\$repo/os/\$arch
EOF
                log_success "저장소 추가됨: $repo_name"
            else
                log_warning "저장소 이미 존재: $repo_name"
            fi
            ;;
            
        *)
            log_error "알 수 없는 저장소 작업: $action"
            return 1
            ;;
    esac
}

# 프로필 기반 패키지 설치
install_profile_packages() {
    local profile="$1"
    local profile_file="$PACKAGES_DIR/package-profiles.yaml"
    
    if [[ ! -f "$profile_file" ]]; then
        log_error "프로필 파일 없음: $profile_file"
        return 1
    fi
    
    log_step "프로필 패키지 설치: $profile"
    
    # 프로필별 패키지 목록
    declare -A profile_packages=(
        ["beginner"]="firefox libreoffice-still vlc gnome-tweaks"
        ["general"]="firefox libreoffice-fresh vlc kdenlive gimp"
        ["developer"]="git vim neovim code docker python nodejs npm"
        ["administrator"]="openssh fail2ban ufw htop iotop"
        ["gamer"]="steam gamemode mangohud"
        ["minimal"]="vim git curl"
        ["enterprise"]="docker kubernetes prometheus grafana ansible"
        ["security"]="nmap wireshark metasploit burpsuite"
    )
    
    local packages="${profile_packages[$profile]:-}"
    
    if [[ -z "$packages" ]]; then
        log_error "알 수 없는 프로필: $profile"
        return 1
    fi
    
    log_info "설치할 패키지: $packages"
    
    # 패키지 설치
    if pacman -S --needed $packages; then
        log_success "프로필 패키지 설치 완료: $profile"
    else
        log_error "프로필 패키지 설치 실패: $profile"
        return 1
    fi
}

# AUR 패키지 관리
manage_aur_packages() {
    local action="$1"
    local package_name="$2"
    
    # yay 또는 paru 확인
    local aur_helper=""
    if command -v yay >/dev/null 2>&1; then
        aur_helper="yay"
    elif command -v paru >/dev/null 2>&1; then
        aur_helper="paru"
    else
        log_error "AUR 헬퍼가 설치되지 않았습니다 (yay 또는 paru 필요)"
        return 1
    fi
    
    case "$action" in
        "install")
            log_step "AUR 패키지 설치: $package_name"
            if $aur_helper -S --needed "$package_name"; then
                log_success "AUR 패키지 설치 완료: $package_name"
            else
                log_error "AUR 패키지 설치 실패: $package_name"
                return 1
            fi
            ;;
            
        "remove")
            log_step "AUR 패키지 제거: $package_name"
            if $aur_helper -Rns "$package_name"; then
                log_success "AUR 패키지 제거 완료: $package_name"
            else
                log_error "AUR 패키지 제거 실패: $package_name"
                return 1
            fi
            ;;
            
        "update")
            log_step "AUR 패키지 업데이트"
            if $aur_helper -Syu; then
                log_success "AUR 패키지 업데이트 완료"
            else
                log_error "AUR 패키지 업데이트 실패"
                return 1
            fi
            ;;
            
        "search")
            log_info "AUR 패키지 검색: $package_name"
            $aur_helper -Ss "$package_name"
            ;;
            
        *)
            log_error "알 수 없는 AUR 작업: $action"
            return 1
            ;;
    esac
}

# 패키지 그룹 관리
manage_package_groups() {
    local action="$1"
    local group_name="$2"
    
    case "$action" in
        "install")
            log_step "패키지 그룹 설치: $group_name"
            if pacman -S "$group_name"; then
                log_success "패키지 그룹 설치 완료: $group_name"
            else
                log_error "패키지 그룹 설치 실패: $group_name"
                return 1
            fi
            ;;
            
        "list")
            log_info "패키지 그룹 목록: $group_name"
            pacman -Sg "$group_name"
            ;;
            
        "info")
            log_info "패키지 그룹 정보: $group_name"
            pacman -Sii "$group_name"
            ;;
            
        *)
            log_error "알 수 없는 그룹 작업: $action"
            return 1
            ;;
    esac
}

# 오래된 패키지 정리
cleanup_old_packages() {
    log_step "오래된 패키지 정리 중..."
    
    local removed_count=0
    
    # 오래된 패키지 제거 (설치되지 않은 의존성)
    if pacman -Rns $(pacman -Qtdq 2>/dev/null) 2>/dev/null; then
        ((removed_count++))
    fi
    
    # 패키지 캐시 정리
    if pacman -Scc --noconfirm; then
        log_success "패키지 캐시 정리 완료"
    fi
    
    # 오래된 로그 파일 정리
    find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null || true
    
    log_success "오래된 패키지 정리 완료"
}

# 패키지 롤백
rollback_packages() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "백업 파일 없음: $backup_file"
        return 1
    fi
    
    log_step "패키지 롤백 중..."
    
    # 백업 파일에서 패키지 목록 추출
    local packages=($(grep -v "^#" "$backup_file" | grep -v "^$"))
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_error "백업 파일에 패키지 정보 없음"
        return 1
    fi
    
    log_info "롤백할 패키지 수: ${#packages[@]}"
    
    # 패키지 롤백
    for package in "${packages[@]}"; do
        local package_name=$(echo "$package" | cut -d' ' -f1)
        local version=$(echo "$package" | cut -d' ' -f2)
        
        log_info "롤백: $package_name ($version)"
        
        # 특정 버전으로 롤백 (캐시에 있는 경우)
        if pacman -S "$package_name=$version" --noconfirm 2>/dev/null; then
            log_success "롤백 완료: $package_name ($version)"
        else
            log_warning "롤백 실패: $package_name ($version)"
        fi
    done
    
    log_success "패키지 롤백 완료"
}

# 패키지 백업
backup_packages() {
    local backup_file="$1"
    
    log_step "패키지 백업 중..."
    
    mkdir -p "$(dirname "$backup_file")"
    
    # 설치된 패키지 목록 생성
    {
        echo "# UnifiedArch OS 패키지 백업"
        echo "# 생성 시간: $(date)"
        echo "# 시스템: $(uname -a)"
        echo ""
        pacman -Qn
    } > "$backup_file"
    
    log_success "패키지 백업 완료: $backup_file"
}

# 패키지 검증
verify_packages() {
    log_step "패키지 무결성 검증 중..."
    
    local failed_packages=()
    
    # 모든 설치된 패키지 검증
    while IFS= read -r package; do
        local package_name=$(echo "$package" | cut -d' ' -f1)
        
        if ! pacman -Qk "$package_name" >/dev/null 2>&1; then
            failed_packages+=("$package_name")
        fi
    done < <(pacman -Qn)
    
    if [[ ${#failed_packages[@]} -eq 0 ]]; then
        log_success "모든 패키지 무결성 검증 통과"
    else
        log_warning "손상된 패키지: ${#failed_packages[@]}개"
        for package in "${failed_packages[@]}"; do
            log_warning "손상된 패키지: $package"
        done
        
        # 손상된 패키지 재설치 제안
        read -p "손상된 패키지를 재설치하시겠습니까? (y/N): " reinstall
        if [[ $reinstall =~ ^[Yy]$ ]]; then
            for package in "${failed_packages[@]}"; do
                log_info "재설치: $package"
                pacman -S "$package" --noconfirm
            done
        fi
    fi
}

# 패키지 통계
show_package_stats() {
    log_info "패키지 통계"
    echo "=================="
    
    # 전체 패키지 수
    local total_packages=$(pacman -Q | wc -l)
    echo "전체 패키지: $total_packages"
    
    # 공식 패키지 수
    local official_packages=$(pacman -Qn | wc -l)
    echo "공식 패키지: $official_packages"
    
    # AUR 패키지 수
    local aur_packages=$(pacman -Qm | wc -l)
    echo "AUR 패키지: $aur_packages"
    
    # 설치 크기
    local install_size=$(pacman -Qi | grep 'Installed Size' | awk '{sum += $4} END {print sum/1024/1024 " GB"}')
    echo "설치 크기: $install_size"
    
    # 최근 업데이트된 패키지
    echo ""
    echo "최근 업데이트 (10개):"
    pacman -Q --sorttime | tail -10 | tac
    
    # 가장 큰 패키지 (10개)
    echo ""
    echo "가장 큰 패키지 (10개):"
    pacman -Qi | awk '/^Name/ {name=$3} /^Installed Size/ {size=$4" "$5; print size, name}' | sort -hr | head -10
}

# 패키지 검색
search_packages() {
    local query="$1"
    local search_type="${2:-name}"
    
    case "$search_type" in
        "name")
            pacman -Ss "$query"
            ;;
        "desc")
            pacman -Ss "^$query" | grep -i "$query"
            ;;
        "file")
            pacman -F "$query"
            ;;
        "all")
            echo "이름 검색:"
            pacman -Ss "$query"
            echo ""
            echo "파일 검색:"
            pacman -F "$query" 2>/dev/null || echo "파일 데이터베이스 없음"
            ;;
        *)
            log_error "알 수 없는 검색 타입: $search_type"
            return 1
            ;;
    esac
}

# 의존성 분석
analyze_dependencies() {
    local package="$1"
    
    if ! pacman -Qi "$package" >/dev/null 2>&1; then
        log_error "패키지 없음: $package"
        return 1
    fi
    
    log_info "의존성 분석: $package"
    echo "=================="
    
    # 직접 의존성
    echo "직접 의존성:"
    pacman -Qi "$package" | grep "Depends On" | cut -d: -f2
    
    # 역 의존성
    echo ""
    echo "역 의존성 (이 패키지를 필요로 함):"
    pacman -Qii "$package" | grep "Required By" | cut -d: -f2
    
    # 선택적 의존성
    echo ""
    echo "선택적 의존성:"
    pacman -Qi "$package" | grep "Optional Deps" | cut -d: -f2
    
    # 의존성 트리
    echo ""
    echo "의존성 트리:"
    pactree "$package" 2>/dev/null || echo "pactree 설치 필요"
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 패키지 관리 시스템"
    echo ""
    echo "사용법: $0 <명령> [인자]"
    echo ""
    echo "기본 명령:"
    echo "  update                    - 패키지 데이터베이스 업데이트"
    echo "  upgrade                   - 시스템 업그레이드"
    echo "  install <package>         - 패키지 설치"
    echo "  remove <package>          - 패키지 제거"
    echo "  search <query> [type]     - 패키지 검색 (name/desc/file/all)"
    echo "  info <package>            - 패키지 정보"
    echo "  list [installed|available] - 패키지 목록"
    echo ""
    echo "고급 명령:"
    echo "  profile <profile>          - 프로필 패키지 설치"
    echo "  aur <action> <package>    - AUR 패키지 관리 (install/remove/update/search)"
    echo "  group <action> <group>    - 패키지 그룹 관리 (install/list/info)"
    echo "  repo <action> <name>      - 저장소 관리 (enable/disable/add)"
    echo "  backup <file>             - 패키지 백업"
    echo "  restore <file>            - 패키지 롤백"
    echo "  verify                    - 패키지 무결성 검증"
    echo "  cleanup                   - 오래된 패키지 정리"
    echo "  stats                     - 패키지 통계"
    echo "  deps <package>            - 의존성 분석"
    echo ""
    echo "프로필: beginner, general, developer, administrator, gaming, minimal, enterprise, security"
}

# 메인 함수
main() {
    local command="${1:-help}"
    
    case "$command" in
        "update")
            check_root
            update_package_db
            ;;
        "upgrade")
            check_root
            check_network
            update_package_db
            pacman -Syu
            ;;
        "install")
            check_root
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: install <package>"
                exit 1
            fi
            pacman -S --needed "$2"
            ;;
        "remove")
            check_root
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: remove <package>"
                exit 1
            fi
            pacman -Rns "$2"
            ;;
        "search")
            if [[ $# -lt 2 ]]; then
                log_error "인자 부족: search <query> [type]"
                exit 1
            fi
            search_packages "$2" "${3:-name}"
            ;;
        "info")
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: info <package>"
                exit 1
            fi
            pacman -Si "$2"
            ;;
        "list")
            local list_type="${2:-installed}"
            case "$list_type" in
                "installed")
                    pacman -Q
                    ;;
                "available")
                    pacman -Sl
                    ;;
                "explicit")
                    pacman -Qe
                    ;;
                *)
                    log_error "알 수 없는 목록 타입: $list_type"
                    exit 1
                    ;;
            esac
            ;;
        "profile")
            check_root
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: profile <profile>"
                exit 1
            fi
            install_profile_packages "$2"
            ;;
        "aur")
            if [[ $# -lt 3 ]]; then
                log_error "인자 부족: aur <action> <package>"
                exit 1
            fi
            manage_aur_packages "$2" "$3"
            ;;
        "group")
            check_root
            if [[ $# -lt 3 ]]; then
                log_error "인자 부족: group <action> <group>"
                exit 1
            fi
            manage_package_groups "$2" "$3"
            ;;
        "repo")
            check_root
            if [[ $# -lt 3 ]]; then
                log_error "인자 부족: repo <action> <name>"
                exit 1
            fi
            manage_repositories "$2" "$3"
            ;;
        "backup")
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: backup <file>"
                exit 1
            fi
            backup_packages "$2"
            ;;
        "restore")
            check_root
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: restore <file>"
                exit 1
            fi
            rollback_packages "$2"
            ;;
        "verify")
            verify_packages
            ;;
        "cleanup")
            check_root
            cleanup_old_packages
            ;;
        "stats")
            show_package_stats
            ;;
        "deps")
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: deps <package>"
                exit 1
            fi
            analyze_dependencies "$2"
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
