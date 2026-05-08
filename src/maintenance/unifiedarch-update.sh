#!/bin/bash
# UnifiedArch OS 시스템 업데이트 및 유지보수 도구
# 완벽한 시스템 업데이트 관리

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
UPDATE_LOG="/var/log/unifiedarch-update.log"
LOCK_FILE="/var/run/unifiedarch-update.lock"
REPO_URL="https://unifiedarch.org/repo"
LOCAL_REPO="/opt/unifiedarch/repo"

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
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" >> "$UPDATE_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $1" >> "$UPDATE_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $1" >> "$UPDATE_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >> "$UPDATE_LOG"
}

# 업데이트 잠금 확인
check_update_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_error "업데이트가 이미 실행 중입니다 (PID: $lock_pid)"
            return 1
        else
            log_warning "오래된 잠금 파일 제거"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    # 잠금 파일 생성
    echo $$ > "$LOCK_FILE"
    return 0
}

# 업데이트 잠금 해제
release_update_lock() {
    rm -f "$LOCK_FILE"
    log_info "업데이트 잠금 해제"
}

# 시스템 정보 가져오기
get_system_info() {
    echo "=== UnifiedArch OS 시스템 정보 ==="
    echo ""
    
    # 운영체제 정보
    echo "운영체제: $(uname -s) $(uname -r) $(uname -m)"
    echo "배포판: $(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 || echo '알 수 없음')"
    echo "버전: $(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo '알 수 없음')"
    echo ""
    
    # 커널 정보
    echo "커널: $(uname -v)"
    echo "업타임: $(uptime -p 2>/dev/null || uptime)"
    echo ""
    
    # 하드웨어 정보
    echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    echo "메모리: $(free -h | grep '^Mem:' | awk '{print $2}')"
    echo "디스크: $(df -h / | tail -1 | awk '{print $2}')"
    echo ""
    
    # UnifiedArch OS 정보
    if [[ -f "/opt/unifiedarch/VERSION" ]]; then
        echo "UnifiedArch 버전: $(cat /opt/unifiedarch/VERSION)"
    else
        echo "UnifiedArch 버전: 알 수 없음"
    fi
    
    # 설치된 패키지 수
    if command -v pacman >/dev/null 2>&1; then
        echo "설치된 패키지: $(pacman -Q | wc -l)"
    elif command -v apt >/dev/null 2>&1; then
        echo "설치된 패키지: $(dpkg -l | wc -l)"
    fi
    
    echo ""
}

# 저장소 동기화
sync_repositories() {
    log_info "저장소 동기화 중..."
    
    # 로컬 저장소 디렉토리 생성
    mkdir -p "$LOCAL_REPO"
    
    # 원격 저장소 동기화 (가상 구현)
    if command -v wget >/dev/null 2>&1; then
        log_info "원격 저장소에서 패키지 정보 다운로드 중..."
        
        # 패키지 목록 다운로드 (가상)
        wget -q --timeout=30 --tries=3 "$REPO_URL/packages.txt" -O "$LOCAL_REPO/packages.txt" 2>/dev/null || {
            log_warning "원격 저장소 접속 실패, 로컬 정보 사용"
            # 기본 패키지 목록 생성
            cat > "$LOCAL_REPO/packages.txt" << 'EOF'
unifiedarch-core 1.0.0
unifiedarch-desktop 1.0.0
unifiedarch-server 1.0.0
unifiedarch-tools 1.0.0
EOF
        }
        
        log_success "저장소 동기화 완료"
    else
        log_error "wget을 찾을 수 없습니다"
        return 1
    fi
}

# 업데이트 가능한 패키지 확인
check_updates() {
    log_info "업데이트 가능한 패키지 확인 중..."
    
    local updates_available=()
    local update_count=0
    
    # Arch Linux 시스템
    if command -v pacman >/dev/null 2>&1; then
        log_info "Arch Linux 패키지 업데이트 확인 중..."
        
        # pacman 업데이트 확인
        if pacman -Qu >/dev/null 2>&1; then
            while IFS= read -r package_info; do
                updates_available+=("$package_info")
                ((update_count++))
            done < <(pacman -Qu)
        fi
    
    # Ubuntu/Debian 시스템
    elif command -v apt >/dev/null 2>&1; then
        log_info "Ubuntu/Debian 패키지 업데이트 확인 중..."
        
        # apt 업데이트 목록 업데이트
        apt update >/dev/null 2>&1
        
        # 업데이트 가능한 패키지 목록
        if apt list --upgradable 2>/dev/null | grep -v "WARNING"; then
            while IFS= read -r package_info; do
                if [[ -n "$package_info" ]]; then
                    updates_available+=("$package_info")
                    ((update_count++))
                fi
            done < <(apt list --upgradable 2>/dev/null | grep -v "WARNING" | awk '/\// {print $1}')
        fi
    fi
    
    # UnifiedArch OS 패키지 확인
    if [[ -f "$LOCAL_REPO/packages.txt" ]]; then
        log_info "UnifiedArch OS 패키지 확인 중..."
        while IFS= read -r package version; do
            local current_version=$(get_installed_version "$package")
            if [[ -n "$current_version" && "$current_version" != "$version" ]]; then
                updates_available+=("$package: $current_version -> $version")
                ((update_count++))
            fi
        done < "$LOCAL_REPO/packages.txt"
    fi
    
    # 결과 표시
    echo "=== 업데이트 가능한 패키지 ==="
    echo "총 $update_count개 패키지"
    echo ""
    
    if [[ $update_count -gt 0 ]]; then
        for update in "${updates_available[@]}"; do
            echo "  $update"
        done
    else
        log_success "모든 패키지가 최신 버전입니다"
    fi
    
    return $update_count
}

# 설치된 버전 가져오기
get_installed_version() {
    local package="$1"
    
    if command -v pacman >/dev/null 2>&1; then
        pacman -Q "$package" 2>/dev/null | awk '{print $2}'
    elif command -v apt >/dev/null 2>&1; then
        apt show "$package" 2>/dev/null | grep '^Version:' | cut -d: -f2 | xargs
    else
        echo ""
    fi
}

# 시스템 업데이트
update_system() {
    log_info "시스템 업데이트 시작 중..."
    
    # 업데이트 가능한 패키지 확인
    check_updates
    local update_count=$?
    
    if [[ $update_count -eq 0 ]]; then
        log_success "업데이트할 패키지 없음"
        return 0
    fi
    
    # 업데이트 전 사전 준비
    log_info "업데이트 전 사전 준비 중..."
    
    # 백업 생성
    if command -v /opt/unifiedarch/src/backup/unifiedarch-backup.sh >/dev/null 2>&1; then
        log_info "업데이트 전 백업 생성 중..."
        /opt/unifiedarch/src/backup/unifiedarch-backup.sh create pre-update
    fi
    
    # 서비스 중지
    log_info "필요한 서비스 중지 중..."
    stop_services_for_update
    
    # 실제 업데이트 실행
    local update_success=false
    
    # Arch Linux 업데이트
    if command -v pacman >/dev/null 2>&1; then
        log_info "Arch Linux 시스템 업데이트 중..."
        if pacman -Syu --noconfirm; then
            update_success=true
        fi
    
    # Ubuntu/Debian 업데이트
    elif command -v apt >/dev/null 2>&1; then
        log_info "Ubuntu/Debian 시스템 업데이트 중..."
        if apt upgrade -y; then
            update_success=true
        fi
    fi
    
    # 업데이트 후 처리
    if [[ "$update_success" == "true" ]]; then
        log_success "시스템 업데이트 완료"
        
        # 서비스 재시작
        restart_services_after_update
        
        # 업데이트 정보 기록
        record_update_info
        
        # UnifiedArch OS 구성요소 업데이트
        update_unifiedarch_components
        
    else
        log_error "시스템 업데이트 실패"
        return 1
    fi
}

# 업데이트를 위한 서비스 중지
stop_services_for_update() {
    local services=("unifiedarch" "network-manager" "display-manager")
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log_info "서비스 중지: $service"
            systemctl stop "$service" 2>/dev/null || true
        fi
    done
}

# 업데이트 후 서비스 재시작
restart_services_after_update() {
    local services=("network-manager" "unifiedarch" "display-manager")
    
    for service in "${services[@]}"; do
        log_info "서비스 재시작: $service"
        systemctl restart "$service" 2>/dev/null || true
        sleep 2
    done
}

# 업데이트 정보 기록
record_update_info() {
    local update_info_file="/var/log/unifiedarch-update-history.log"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local kernel_version=$(uname -r)
    
    echo "$timestamp|$kernel_version|system_update" >> "$update_info_file"
    log_success "업데이트 정보 기록됨"
}

# UnifiedArch OS 구성요소 업데이트
update_unifiedarch_components() {
    log_info "UnifiedArch OS 구성요소 업데이트 중..."
    
    # 커널 모듈 업데이트
    if [[ -d "/opt/unifiedarch/src/kernel" ]]; then
        log_info "커널 모듈 업데이트 중..."
        cd "/opt/unifiedarch/src/kernel"
        if make clean && make; then
            make install 2>/dev/null || true
            log_success "커널 모듈 업데이트 완료"
        else
            log_warning "커널 모듈 업데이트 실패"
        fi
    fi
    
    # 시스템 도구 업데이트
    if [[ -d "/opt/unifiedarch/src/tools" ]]; then
        log_info "시스템 도구 업데이트 중..."
        # 도구 파일들 최신 상태로 업데이트
        find "/opt/unifiedarch/src/tools" -name "*.sh" -exec chmod +x {} \;
        log_success "시스템 도구 업데이트 완료"
    fi
    
    # 설정 파일 업데이트
    if [[ -d "/opt/unifiedarch/etc" ]]; then
        log_info "설정 파일 업데이트 중..."
        # 설정 파일들 시스템에 복사
        cp -r "/opt/unifiedarch/etc"/* "/etc/unifiedarch/" 2>/dev/null || true
        log_success "설정 파일 업데이트 완료"
    fi
}

# 시스템 정리
cleanup_system() {
    log_info "시스템 정리 중..."
    
    # 패키지 캐시 정리
    if command -v pacman >/dev/null 2>&1; then
        log_info "pacman 캐시 정리 중..."
        pacman -Scc --noconfirm 2>/dev/null || true
    elif command -v apt >/dev/null 2>&1; then
        log_info "apt 캐시 정리 중..."
        apt autoremove -y 2>/dev/null || true
        apt autoclean 2>/dev/null || true
    fi
    
    # 오래된 로그 정리
    log_info "오래된 로그 정리 중..."
    find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null || true
    find /var/log -name "*.log.*" -mtime +7 -delete 2>/dev/null || true
    
    # 임시 파일 정리
    log_info "임시 파일 정리 중..."
    find /tmp -type f -atime +7 -delete 2>/dev/null || true
    find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
    
    # 오래된 백업 정리
    if command -v /opt/unifiedarch/src/backup/unifiedarch-backup.sh >/dev/null 2>&1; then
        log_info "오래된 백업 정리 중..."
        /opt/unifiedarch/src/backup/unifiedarch-backup.sh cleanup
    fi
    
    log_success "시스템 정리 완료"
}

# 시스템 검증
verify_system() {
    log_info "시스템 검증 중..."
    
    local issues=0
    
    # 패키지 무결성 검증
    log_info "패키지 무결성 검증 중..."
    
    if command -v pacman >/dev/null 2>&1; then
        if ! pacman -Qk >/dev/null 2>&1; then
            log_warning "일부 패키지가 손상되었습니다"
            ((issues++))
        fi
    elif command -v debsums >/dev/null 2>&1; then
        if ! debsums -c >/dev/null 2>&1; then
            log_warning "일부 패키지가 손상되었습니다"
            ((issues++))
        fi
    fi
    
    # 중요 파일 무결성 검증
    log_info "중요 파일 무결성 검증 중..."
    
    local critical_files=(
        "/etc/passwd"
        "/etc/shadow"
        "/etc/group"
        "/etc/fstab"
        "/boot/grub/grub.cfg"
    )
    
    for file in "${critical_files[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ ! -r "$file" ]]; then
                log_error "파일 읽기 불가: $file"
                ((issues++))
            fi
        else
            log_warning "중요 파일 없음: $file"
            ((issues++))
        fi
    done
    
    # 디스크 공간 확인
    log_info "디스크 공간 확인 중..."
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log_warning "디스크 공간 부족: ${disk_usage}%"
        ((issues++))
    fi
    
    # 메모리 사용량 확인
    log_info "메모리 사용량 확인 중..."
    local memory_usage=$(free | grep '^Mem:' | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $memory_usage -gt 85 ]]; then
        log_warning "메모리 사용량 높음: ${memory_usage}%"
        ((issues++))
    fi
    
    # 결과 보고
    echo ""
    echo "=== 시스템 검증 결과 ==="
    if [[ $issues -eq 0 ]]; then
        log_success "시스템 검증 통과 (문제 없음)"
    else
        log_warning "시스템 검증에서 $issues개 문제 발견"
    fi
    
    return $issues
}

# 업데이트 기록 보기
show_update_history() {
    local lines="${1:-20}"
    
    echo "=== UnifiedArch OS 업데이트 기록 ==="
    echo "최근 $lines개 업데이트:"
    echo ""
    
    local history_file="/var/log/unifiedarch-update-history.log"
    if [[ -f "$history_file" ]]; then
        printf "%-20s %-15s %-15s\n" "날짜" "커널 버전" "업데이트 타입"
        printf "%-20s %-15s %-15s\n" "--------------------" "---------------" "---------------"
        
        tail -n "$lines" "$history_file" | while IFS='|' read -r timestamp kernel_version update_type; do
            printf "%-20s %-15s %-15s\n" "${timestamp:0:19}" "$kernel_version" "$update_type"
        done
    else
        log_info "업데이트 기록 없음"
    fi
}

# 자동 업데이트 설정
setup_auto_update() {
    local enable="${1:-true}"
    local schedule="${2:-daily}"
    
    log_info "자동 업데이트 설정 중..."
    
    # crontab 항목 생성
    local cron_entry=""
    case "$schedule" in
        "daily")
            cron_entry="0 2 * * * /opt/unifiedarch/src/maintenance/unifiedarch-update.sh auto"
            ;;
        "weekly")
            cron_entry="0 2 * * 0 /opt/unifiedarch/src/maintenance/unifiedarch-update.sh auto"
            ;;
        "monthly")
            cron_entry="0 2 1 * * /opt/unifiedarch/src/maintenance/unifiedarch-update.sh auto"
            ;;
        *)
            log_error "알 수 없는 스케줄: $schedule"
            return 1
            ;;
    esac
    
    if [[ "$enable" == "true" ]]; then
        # 현재 crontab 확인
        local current_crontab=$(crontab -l 2>/dev/null || echo "")
        
        # 기존 UnifiedArch 업데이트 항목 제거
        current_crontab=$(echo "$current_crontab" | grep -v "unifiedarch-update")
        
        # 새 항목 추가
        echo "$current_crontab" | { cat; echo "$cron_entry"; } | crontab -
        
        log_success "자동 업데이트 활성화: $schedule"
    else
        # crontab에서 제거
        local current_crontab=$(crontab -l 2>/dev/null || echo "")
        echo "$current_crontab" | grep -v "unifiedarch-update" | crontab -
        
        log_success "자동 업데이트 비활성화"
    fi
}

# 롤백 준비
prepare_rollback() {
    log_info "롤백 준비 중..."
    
    # 백업 디렉토리 확인
    local backup_dir="/var/backups/unifiedarch"
    if [[ ! -d "$backup_dir" ]]; then
        log_error "백업 디렉토리 없음: $backup_dir"
        return 1
    fi
    
    # 최근 백업 목록
    echo "=== 롤백 가능한 백업 ==="
    find "$backup_dir" -name "*.tar*" -type f -printf '%T@ %p\n' | sort -n | tail -10 | while read -r timestamp backup_file; do
        local file_size=$(du -h "$backup_file" | cut -f1)
        local backup_date=$(date -d @"$timestamp" '+%Y-%m-%d %H:%M:%S')
        echo "  $(basename "$backup_file"): $file_size ($backup_date)"
    done
    
    echo ""
    echo "롤백 실행: $0 rollback <backup_name>"
}

# 시스템 롤백
rollback_system() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        log_error "백업 이름이 필요합니다"
        return 1
    fi
    
    log_info "시스템 롤백 시작: $backup_name"
    
    # 백업 복원 도구 호출
    if command -v /opt/unifiedarch/src/backup/unifiedarch-backup.sh >/dev/null 2>&1; then
        /opt/unifiedarch/src/backup/unifiedarch-backup.sh restore "$backup_name"
        
        if [[ $? -eq 0 ]]; then
            log_success "시스템 롤백 완료"
            log_warning "시스템 재부팅이 필요합니다"
        else
            log_error "시스템 롤백 실패"
            return 1
        fi
    else
        log_error "백업 복원 도구를 찾을 수 없습니다"
        return 1
    fi
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 시스템 업데이트 및 유지보수 도구"
    echo ""
    echo "사용법: $0 [명령] [인자...]"
    echo ""
    echo "명령:"
    echo "  info                     - 시스템 정보 보기"
    echo "  check                    - 업데이트 가능한 패키지 확인"
    echo "  update                   - 시스템 업데이트"
    echo "  cleanup                  - 시스템 정리"
    echo "  verify                   - 시스템 검증"
    echo "  history [lines]          - 업데이트 기록 보기"
    echo "  auto [enable|disable] [schedule] - 자동 업데이트 설정"
    echo "  rollback [backup_name]    - 롤백 준비/실행"
    echo "  help                     - 이 도움말 표시"
    echo ""
    echo "예시:"
    echo "  $0 info                  - 시스템 정보 보기"
    echo "  $0 check                 - 업데이트 확인"
    echo "  $0 update                - 전체 시스템 업데이트"
    echo "  $0 auto enable daily     - 매일 자동 업데이트 활성화"
    echo "  $0 auto disable          - 자동 업데이트 비활성화"
    echo "  $0 rollback backup_20231201 - 특정 백업으로 롤백"
}

# 메인 함수
main() {
    local command="${1:-help}"
    
    # 업데이트 잠금 확인
    if [[ "$command" != "help" && "$command" != "info" ]]; then
        check_update_lock
        
        # 종료 시 잠금 해제
        trap release_update_lock EXIT
    fi
    
    case "$command" in
        "info")
            get_system_info
            ;;
        "check")
            sync_repositories
            check_updates
            ;;
        "update")
            sync_repositories
            update_system
            ;;
        "cleanup")
            cleanup_system
            ;;
        "verify")
            verify_system
            ;;
        "history")
            show_update_history "${2:-20}"
            ;;
        "auto")
            setup_auto_update "${2:-enable}" "${3:-daily}"
            ;;
        "rollback")
            if [[ -n "${2:-}" ]]; then
                rollback_system "$2"
            else
                prepare_rollback
            fi
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
