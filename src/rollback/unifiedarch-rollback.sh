#!/bin/bash
#
# UnifiedArch OS Update Rollback System
# 업데이트 롤백 및 복구 시스템
#
# 기능:
# - Btrfs 스냅샷 자동 생성
# - 부팅 실패 시 자동 복원
# - 패키지 롤백
# - 시스템 상태 백업/복원
#

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
ROLLBACK_DIR="/var/lib/unifiedarch/rollback"
SNAPSHOT_DIR="/.snapshots"
BACKUP_DIR="/var/backups/unifiedarch"
LOG_FILE="/var/log/unifiedarch-rollback.log"

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
log_rollback() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 루트 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "루트 권한이 필요합니다"
        exit 1
    fi
}

# Btrfs 확인
check_btrfs() {
    local root_fs=$(findmnt -n -o FSTYPE /)
    
    if [[ "$root_fs" != "btrfs" ]]; then
        log_warning "루트 파일시스템이 Btrfs가 아님: $root_fs"
        log_info "Btrfs 스냅샷 기능이 제한됩니다"
        return 1
    fi
    
    return 0
}

# 디렉토리 생성
create_directories() {
    mkdir -p "$ROLLBACK_DIR" "$BACKUP_DIR"
    mkdir -p "$SNAPSHOT_DIR/pre-update"
    mkdir -p "$SNAPSHOT_DIR/post-update"
    mkdir -p "$SNAPSHOT_DIR/boot-backup"
    mkdir -p "$SNAPSHOT_DIR/system-backup"
    chmod 755 "$ROLLBACK_DIR" "$BACKUP_DIR"
}

# Btrfs 스냅샷 생성
create_snapshot() {
    local snapshot_name="$1"
    local description="$2"
    
    log_step "Btrfs 스냅샷 생성 중: $snapshot_name"
    
    if ! check_btrfs; then
        log_error "Btrfs 파일시스템이 아님"
        return 1
    fi
    
    local snapshot_path="$SNAPSHOT_DIR/$snapshot_name"
    local root_mount=$(findmnt -n -o SOURCE /)
    
    # 스냅샷 생성
    if btrfs subvolume snapshot "$root_mount" "$snapshot_path" 2>/dev/null; then
        log_success "스냅샷 생성 완료: $snapshot_path"
        
        # 스냅샷 메타데이터 저장
        cat > "$ROLLBACK_DIR/$snapshot_name.meta" << EOF
snapshot_name=$snapshot_name
description=$description
created_at=$(date +%s)
created_date=$(date '+%Y-%m-%d %H:%M:%S')
kernel_version=$(uname -r)
root_uuid=$(findmnt -n -o UUID /)
size_bytes=$(du -sb "$snapshot_path" | cut -f1)
size_human=$(du -sh "$snapshot_path" | cut -f1)
EOF
        
        log_rollback "스냅샷 생성: $snapshot_name - $description"
        return 0
    else
        log_error "스냅샷 생성 실패: $snapshot_name"
        return 1
    fi
}

# 업데이트 전 스냅샷
create_pre_update_snapshot() {
    local snapshot_name="pre-update-$(date +%Y%m%d-%H%M%S)"
    local description="업데이트 전 시스템 상태"
    
    create_snapshot "$snapshot_name" "$description"
    echo "$snapshot_name" > "$ROLLBACK_DIR/last-pre-update"
}

# 업데이트 후 스냅샷
create_post_update_snapshot() {
    local snapshot_name="post-update-$(date +%Y%m%d-%H%M%S)"
    local description="업데이트 후 시스템 상태"
    
    create_snapshot "$snapshot_name" "$description"
    echo "$snapshot_name" > "$ROLLBACK_DIR/last-post-update"
}

# 스냅샷 목록
list_snapshots() {
    log_step "스냅샷 목록 표시 중..."
    
    echo ""
    echo "========================================="
    echo "           Btrfs 스냅샷 목록"
    echo "========================================="
    echo ""
    
    printf "%-20s %-30s %-15s %-10s\n" "이름" "설명" "생성 시간" "크기"
    echo "------------------------------------------------------------------------"
    
    for meta_file in "$ROLLBACK_DIR"/*.meta; do
        if [[ -f "$meta_file" ]]; then
            local snapshot_name=$(basename "$meta_file" .meta)
            source "$meta_file"
            
            printf "%-20s %-30s %-15s %-10s\n" \
                "$snapshot_name" \
                "$description" \
                "$created_date" \
                "$size_human"
        fi
    done
    
    echo ""
    echo "총 스냅샷: $(ls -1 "$ROLLBACK_DIR"/*.meta 2>/dev/null | wc -l)개"
    echo "========================================="
}

# 스냅샷 복원
restore_snapshot() {
    local snapshot_name="$1"
    local snapshot_path="$SNAPSHOT_DIR/$snapshot_name"
    
    log_step "스냅샷 복원 중: $snapshot_name"
    
    if [[ ! -d "$snapshot_path" ]]; then
        log_error "스냅샷을 찾을 수 없음: $snapshot_name"
        return 1
    fi
    
    if [[ ! -f "$ROLLBACK_DIR/$snapshot_name.meta" ]]; then
        log_error "스냅샷 메타데이터를 찾을 수 없음: $snapshot_name"
        return 1
    fi
    
    # 현재 루트 백업
    local current_backup="current-backup-$(date +%Y%m%d-%H%M%S)"
    local root_mount=$(findmnt -n -o SOURCE /)
    
    if btrfs subvolume snapshot "$root_mount" "$SNAPSHOT_DIR/$current_backup" 2>/dev/null; then
        log_info "현재 상태 백업: $current_backup"
    else
        log_warning "현재 상태 백업 실패"
    fi
    
    # 읽기 전용으로 리마운트
    mount -o remount,ro / 2>/dev/null || {
        log_error "루트 파일시스템 리마운트 실패"
        return 1
    }
    
    # 현재 서브볼륨 삭제
    if btrfs subvolume delete "$root_mount" 2>/dev/null; then
        log_info "현재 서브볼륨 삭제 완료"
    else
        log_error "현재 서브볼륨 삭제 실패"
        mount -o remount,rw / 2>/dev/null
        return 1
    fi
    
    # 스냅샷을 루트로 복원
    if btrfs subvolume snapshot "$snapshot_path" "$root_mount" 2>/dev/null; then
        log_success "스냅샷 복원 완료: $snapshot_name"
        
        # 쓰기 모드로 리마운트
        mount -o remount,rw / 2>/dev/null || {
            log_error "쓰기 모드 리마운트 실패"
            return 1
        }
        
        log_rollback "스냅샷 복원: $snapshot_name"
        
        # 복원 후 작업
        post_restore_actions "$snapshot_name"
        
        log_success "시스템 복원 완료 - 재부팅 필요"
        echo "재부팅하시겠습니까? (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            reboot
        fi
    else
        log_error "스냅샷 복원 실패: $snapshot_name"
        mount -o remount,rw / 2>/dev/null
        return 1
    fi
}

# 복원 후 작업
post_restore_actions() {
    local snapshot_name="$1"
    
    log_step "복원 후 작업 수행 중..."
    
    # 패키지 데이터베이스 업데이트
    if command -v pacman &>/dev/null; then
        pacman -Fy 2>/dev/null || log_warning "패키지 데이터베이스 업데이트 실패"
    fi
    
    # GRUB 설정 업데이트
    if command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || log_warning "GRUB 설정 업데이트 실패"
    fi
    
    # initramfs 재생성
    if command -v mkinitcpio &>/dev/null; then
        mkinitcpio -P linux 2>/dev/null || log_warning "initramfs 재생성 실패"
    fi
    
    log_rollback "복원 후 작업 완료: $snapshot_name"
}

# 패키지 롤백
rollback_packages() {
    local backup_name="$1"
    
    log_step "패키지 롤백 중: $backup_name"
    
    local backup_file="$BACKUP_DIR/packages-$backup_name.tar.gz"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "패키지 백업을 찾을 수 없음: $backup_name"
        return 1
    fi
    
    # 현재 패키지 백업
    local current_backup="packages-current-$(date +%Y%m%d-%H%M%S).tar.gz"
    pacman -Qqe | gzip > "$BACKUP_DIR/$current_backup" 2>/dev/null || {
        log_error "현재 패키지 백업 실패"
        return 1
    }
    
    # 패키지 롤백
    cd /
    if tar -xzf "$backup_file" 2>/dev/null; then
        # 불필요 패키지 제거
        pacman -Rns $(pacman -Qq) 2>/dev/null || log_warning "패키지 제거 실패"
        
        # 백업된 패키지 설치
        pacman -S --needed --noconfirm $(cat "$BACKUP_DIR/packages-$backup_name") 2>/dev/null || {
            log_error "패키지 설치 실패"
            return 1
        }
        
        log_success "패키지 롤백 완료: $backup_name"
        log_rollback "패키지 롤백: $backup_name"
    else
        log_error "패키지 롤백 실패: $backup_name"
        return 1
    fi
}

# 패키지 백업
backup_packages() {
    local backup_name="$1"
    
    log_step "패키지 백업 중: $backup_name"
    
    local backup_file="$BACKUP_DIR/packages-$backup_name.tar.gz"
    
    if pacman -Qqe | gzip > "$backup_file" 2>/dev/null; then
        log_success "패키지 백업 완료: $backup_name"
        log_rollback "패키지 백업: $backup_name"
    else
        log_error "패키지 백업 실패: $backup_name"
        return 1
    fi
}

# 자동 롤백 설정
setup_auto_rollback() {
    log_step "자동 롤백 설정 중..."
    
    # systemd 서비스 생성
    cat > /etc/systemd/system/unifiedarch-rollback.service << 'EOF'
[Unit]
Description=UnifiedArch OS Automatic Rollback Service
DefaultDependencies=no
After=local-fs.target
Before=systemd-user-sessions.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/unifiedarch-auto-rollback
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # 자동 롤백 스크립트
    cat > /usr/local/bin/unifiedarch-auto-rollback << 'EOF'
#!/bin/bash
# UnifiedArch OS 자동 롤백 스크립트

ROLLBACK_DIR="/var/lib/unifiedarch/rollback"
LOG_FILE="/var/log/unifiedarch-rollback.log"
MAX_BOOT_ATTEMPTS=3

log_rollback() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] AUTO: $1" >> "$LOG_FILE"
}

# 부팅 실패 감지
check_boot_failure() {
    local boot_count_file="$ROLLBACK_DIR/boot-count"
    local boot_count=1
    
    if [[ -f "$boot_count_file" ]]; then
        boot_count=$(cat "$boot_count_file")
        boot_count=$((boot_count + 1))
    fi
    
    echo "$boot_count" > "$boot_count_file"
    
    # 이전 부팅 성공 확인
    if [[ $boot_count -gt 1 ]]; then
        local last_boot_status="$ROLLBACK_DIR/last-boot-status"
        if [[ -f "$last_boot_status" && "$(cat "$last_boot_status")" == "success" ]]; then
            # 부팅 성공했으면 카운터 리셋
            echo "1" > "$boot_count_file"
            echo "success" > "$last_boot_status"
            log_rollback "부팅 성공 확인 - 카운터 리셋"
            return 1
        fi
    fi
    
    # 부팅 실패 횟수 확인
    if [[ $boot_count -gt $MAX_BOOT_ATTEMPTS ]]; then
        log_rollback "부팅 실패 횟수 초과: $boot_count"
        return 0
    fi
    
    echo "success" > "$last_boot_status"
    return 1
}

# 자동 롤백 실행
perform_auto_rollback() {
    log_rollback "자동 롤백 시작"
    
    # 마지막 성공 스냅샷 찾기
    local last_snapshot=$(cat "$ROLLBACK_DIR/last-post-update" 2>/dev/null)
    
    if [[ -n "$last_snapshot" ]]; then
        /usr/local/bin/unifiedarch-rollback restore "$last_snapshot"
        log_rollback "자동 롤백 실행: $last_snapshot"
    else
        log_rollback "복구할 스냅샷 없음"
    fi
}

# 메인 함수
main() {
    log_rollback "자동 롤백 서비스 시작"
    
    # 부팅 실패 확인
    if check_boot_failure; then
        perform_auto_rollback
    else
        # 시스템 정상 부팅 - 30초 후 성공 기록
        sleep 30
        echo "success" > "$ROLLBACK_DIR/last-boot-status"
        log_rollback "시스템 정상 부팅 완료"
    fi
}
EOF
    
    chmod +x /usr/local/bin/unifiedarch-auto-rollback
    
    # 서비스 활성화
    systemctl enable unifiedarch-rollback.service 2>/dev/null || log_warning "자동 롤백 서비스 활성화 실패"
    
    log_success "자동 롤백 설정 완료"
}

# 스냅샷 정리
cleanup_snapshots() {
    log_step "오래된 스냅샷 정리 중..."
    
    local max_snapshots=10
    local snapshot_count=$(ls -1 "$ROLLBACK_DIR"/*.meta 2>/dev/null | wc -l)
    
    if [[ $snapshot_count -le $max_snapshots ]]; then
        log_info "정리할 스냅샷 없음"
        return 0
    fi
    
    # 오래된 스냅샷 찾기
    find "$ROLLBACK_DIR" -name "*.meta" -printf "%T@ %p\n" | \
        sort -n | head -n -$((snapshot_count - max_snapshots)) | \
        cut -d' ' ' -f2- | while read meta_file; do
            local snapshot_name=$(basename "$meta_file" .meta)
            local snapshot_path="$SNAPSHOT_DIR/$snapshot_name"
            
            log_info "오래된 스냅샷 삭제: $snapshot_name"
            btrfs subvolume delete "$snapshot_path" 2>/dev/null || log_warning "스냅샷 삭제 실패: $snapshot_name"
            rm -f "$meta_file" 2>/dev/null || log_warning "메타데이터 삭제 실패: $snapshot_name"
        done
    
    log_success "스냅샷 정리 완료"
}

# 롤백 상태 표시
show_rollback_status() {
    echo ""
    echo "========================================="
    echo "        롤백 시스템 상태"
    echo "========================================="
    echo ""
    
    # 파일시스템 정보
    echo "파일시스템:"
    local root_fs=$(findmnt -n -o FSTYPE /)
    echo "  루트: $root_fs"
    
    if [[ "$root_fs" == "btrfs" ]]; then
        echo "  스냅샷 지원: 예"
        local snapshot_count=$(ls -1 "$SNAPSHOT_DIR" 2>/dev/null | wc -l)
        echo "  스냅샷 수: $snapshot_count"
    else
        echo "  스냅샷 지원: 아니오"
    fi
    
    echo ""
    echo "자동 롤백:"
    if systemctl is-enabled unifiedarch-rollback.service &>/dev/null; then
        echo "  서비스: 활성화"
        local boot_count=$(cat "$ROLLBACK_DIR/boot-count" 2>/dev/null || echo "0")
        echo "  부팅 시도: $boot_count"
    else
        echo "  서비스: 비활성화"
    fi
    
    echo ""
    echo "최근 작업:"
    if [[ -f "$LOG_FILE" ]]; then
        tail -5 "$LOG_FILE" | while read line; do
            echo "  $line"
        done
    else
        echo "  로그 없음"
    fi
    
    echo "========================================="
}

# 도움말
show_help() {
    echo "UnifiedArch OS Update Rollback System"
    echo ""
    echo "사용법: $0 [명령어] [인자]"
    echo ""
    echo "명령어:"
    echo "  snapshot <name> <desc>  - 스냅샷 생성"
    echo "  pre-update                 - 업데이트 전 스냅샷"
    echo "  post-update                - 업데이트 후 스냅샷"
    echo "  restore <name>            - 스냅샷 복원"
    echo "  list                      - 스냅샷 목록"
    echo "  backup-packages <name>    - 패키지 백업"
    echo "  rollback-packages <name>  - 패키지 롤백"
    echo "  setup-auto               - 자동 롤백 설정"
    echo "  cleanup                  - 오래된 스냅샷 정리"
    echo "  status                   - 롤백 상태 표시"
    echo "  help                     - 이 도움말"
    echo ""
    echo "예시:"
    echo "  $0 snapshot pre-update-20231201 '업데이트 전'"
    echo "  $0 restore pre-update-20231201"
    echo "  $0 setup-auto"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    check_root
    create_directories
    
    case "$action" in
        snapshot)
            if [[ $# -ne 3 ]]; then
                log_error "인자 부족: $0 snapshot <name> <description>"
                exit 1
            fi
            create_snapshot "$2" "$3"
            ;;
        pre-update)
            create_pre_update_snapshot
            ;;
        post-update)
            create_post_update_snapshot
            ;;
        restore)
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: $0 restore <snapshot_name>"
                exit 1
            fi
            restore_snapshot "$2"
            ;;
        list)
            list_snapshots
            ;;
        backup-packages)
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: $0 backup-packages <name>"
                exit 1
            fi
            backup_packages "$2"
            ;;
        rollback-packages)
            if [[ $# -ne 2 ]]; then
                log_error "인자 부족: $0 rollback-packages <backup_name>"
                exit 1
            fi
            rollback_packages "$2"
            ;;
        setup-auto)
            setup_auto_rollback
            ;;
        cleanup)
            cleanup_snapshots
            ;;
        status)
            show_rollback_status
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
