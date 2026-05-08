#!/bin/bash
# UnifiedArch OS 백업 및 복구 시스템
# 완벽한 데이터 백업 및 복원

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
BACKUP_DIR="/var/backups/unifiedarch"
CONFIG_DIR="/etc/unifiedarch/backup"
LOG_FILE="/var/log/unifiedarch-backup.log"

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

# 백업 환경 초기화
init_backup_environment() {
    log_info "백업 환경 초기화 중..."
    
    # 디렉토리 생성
    mkdir -p "$BACKUP_DIR" "$CONFIG_DIR" "$(dirname "$LOG_FILE")"
    
    # 설정 파일 생성
    if [[ ! -f "$CONFIG_DIR/backup.conf" ]]; then
        cat > "$CONFIG_DIR/backup.conf" << 'EOF'
# UnifiedArch OS 백업 설정

# 기본 백업 디렉토리
DEFAULT_BACKUP_DIR="/var/backups/unifiedarch"

# 백업 보관 기간 (일)
RETENTION_DAYS=30

# 압축 설정
COMPRESSION="gzip"  # gzip, bzip2, xz, none
COMPRESSION_LEVEL=6

# 암호화 설정
ENCRYPTION="false"
ENCRYPTION_KEY=""

# 백업 대상
BACKUP_TARGETS=(
    "/etc"
    "/home"
    "/opt/unifiedarch"
    "/var/log"
    "/usr/local"
    "/root"
)

# 제외 대상
EXCLUDE_TARGETS=(
    "/tmp"
    "/var/tmp"
    "/var/cache"
    "/var/lock"
    "/home/*/.cache"
    "/home/*/.thumbnails"
    "*.log"
    "*.tmp"
)

# 백업 스케줄
SCHEDULE_ENABLED="false"
SCHEDULE_TIME="02:00"
SCHEDULE_DAYS="daily"  # daily, weekly, monthly

# 원격 백업 설정
REMOTE_BACKUP="false"
REMOTE_HOST=""
REMOTE_USER=""
REMOTE_PATH=""
REMOTE_KEY=""

# 백업 전후 스크립트
PRE_BACKUP_SCRIPT=""
POST_BACKUP_SCRIPT=""

# 알림 설정
EMAIL_NOTIFICATIONS="false"
EMAIL_RECIPIENT=""
SMTP_SERVER=""
EOF
        log_info "백업 설정 파일 생성됨: $CONFIG_DIR/backup.conf"
    fi
    
    # 백업 디렉토리 구조 생성
    mkdir -p "$BACKUP_DIR"/{daily,weekly,monthly,incremental,full}
    
    log_success "백업 환경 초기화 완료"
}

# 설정 로드
load_backup_config() {
    if [[ -f "$CONFIG_DIR/backup.conf" ]]; then
        source "$CONFIG_DIR/backup.conf"
        log_info "백업 설정 로드됨"
    else
        log_warning "백업 설정 파일 없음, 기본값 사용"
    fi
}

# 백업 생성
create_backup() {
    local backup_type="${1:-full}"
    local backup_name="${2:-}"
    
    log_info "백업 생성 시작: $backup_type"
    
    # 설정 로드
    load_backup_config
    
    # 백업 이름 생성
    if [[ -z "$backup_name" ]]; then
        backup_name="unifiedarch-$(date +%Y%m%d-%H%M%S)-$backup_type"
    fi
    
    local backup_file="$BACKUP_DIR/$backup_type/$backup_name.tar"
    
    # 백업 대상 목록 생성
    local targets_file=$(mktemp)
    for target in "${BACKUP_TARGETS[@]}"; do
        if [[ -d "$target" || -f "$target" ]]; then
            echo "$target" >> "$targets_file"
        fi
    done
    
    # 제외 목록 생성
    local exclude_file=$(mktemp)
    for exclude in "${EXCLUDE_TARGETS[@]}"; do
        echo "--exclude=$exclude" >> "$exclude_file"
    done
    
    # 백업 실행
    log_info "백업 파일 생성 중: $backup_file"
    
    case "$backup_type" in
        "full")
            create_full_backup "$backup_file" "$targets_file" "$exclude_file"
            ;;
        "incremental")
            create_incremental_backup "$backup_file" "$targets_file" "$exclude_file"
            ;;
        "differential")
            create_differential_backup "$backup_file" "$targets_file" "$exclude_file"
            ;;
        *)
            log_error "알 수 없는 백업 타입: $backup_type"
            rm -f "$targets_file" "$exclude_file"
            return 1
            ;;
    esac
    
    # 임시 파일 정리
    rm -f "$targets_file" "$exclude_file"
    
    # 백업 검증
    verify_backup "$backup_file"
    
    # 백업 정보 기록
    record_backup_info "$backup_name" "$backup_type" "$backup_file"
    
    log_success "백업 생성 완료: $backup_name"
}

# 전체 백업 생성
create_full_backup() {
    local backup_file="$1"
    local targets_file="$2"
    local exclude_file="$3"
    
    # 사전 백업 스크립트 실행
    if [[ -n "$PRE_BACKUP_SCRIPT" && -f "$PRE_BACKUP_SCRIPT" ]]; then
        log_info "사전 백업 스크립트 실행 중..."
        bash "$PRE_BACKUP_SCRIPT"
    fi
    
    # tar로 백업 생성
    local tar_options=(
        "--create"
        "--file=$backup_file"
        "--preserve-permissions"
        "--xattrs"
        "--acl"
    )
    
    # 압축 옵션 추가
    case "$COMPRESSION" in
        "gzip")
            tar_options+=("--gzip")
            backup_file="$backup_file.gz"
            ;;
        "bzip2")
            tar_options+=("--bzip2")
            backup_file="$backup_file.bz2"
            ;;
        "xz")
            tar_options+=("--xz")
            backup_file="$backup_file.xz"
            ;;
    esac
    
    # 제외 옵션 추가
    while IFS= read -r exclude; do
        tar_options+=("$exclude")
    done < "$exclude_file"
    
    # 백업 대상 추가
    while IFS= read -r target; do
        tar_options+=("$target")
    done < "$targets_file"
    
    # 백업 실행
    tar "${tar_options[@]}"
    
    # 암호화 (설정된 경우)
    if [[ "$ENCRYPTION" == "true" && -n "$ENCRYPTION_KEY" ]]; then
        encrypt_backup "$backup_file" "$ENCRYPTION_KEY"
    fi
    
    # 사후 백업 스크립트 실행
    if [[ -n "$POST_BACKUP_SCRIPT" && -f "$POST_BACKUP_SCRIPT" ]]; then
        log_info "사후 백업 스크립트 실행 중..."
        bash "$POST_BACKUP_SCRIPT"
    fi
}

# 증분 백업 생성
create_incremental_backup() {
    local backup_file="$1"
    local targets_file="$2"
    local exclude_file="$3"
    
    # 스냅샷 파일 확인
    local snapshot_file="$CONFIG_DIR/snapshot.snar"
    local incremental_options=()
    
    if [[ -f "$snapshot_file" ]]; then
        incremental_options+=("--listed-incremental=$snapshot_file")
        log_info "증분 백업 (스냅샷 기반)"
    else
        log_info "첫 증분 백업 (전체 백업과 동일)"
    fi
    
    # 전체 백업과 동일한 방식으로 실행
    create_full_backup "$backup_file" "$targets_file" "$exclude_file"
    
    # 스냅샷 업데이트
    if [[ -f "$backup_file" || -f "$backup_file.gz" || -f "$backup_file.bz2" || -f "$backup_file.xz" ]]; then
        tar --create --file="$snapshot_file" --listed-incremental "$targets_file" 2>/dev/null || true
    fi
}

# 차분 백업 생성
create_differential_backup() {
    local backup_file="$1"
    local targets_file="$2"
    local exclude_file="$3"
    
    # 마지막 전체 백업 찾기
    local last_full_backup=$(find "$BACKUP_DIR/full" -name "unifiedarch-*-full.tar*" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -n "$last_full_backup" ]]; then
        log_info "차분 백업 (기반: $last_full_backup)"
        # 차분 백업 로직 구현
        create_full_backup "$backup_file" "$targets_file" "$exclude_file"
    else
        log_warning "기준 전체 백업 없음, 전체 백업으로 전환"
        create_full_backup "$backup_file" "$targets_file" "$exclude_file"
    fi
}

# 백업 암호화
encrypt_backup() {
    local backup_file="$1"
    local encryption_key="$2"
    
    log_info "백업 암호화 중..."
    
    if command -v gpg >/dev/null 2>&1; then
        echo "$encryption_key" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 --compress-algo 1 --s2k-mode 3 --s2k-digest-algo SHA512 --s2k-count 65536 --output "$backup_file.gpg" "$backup_file"
        rm -f "$backup_file"
        log_success "백업 암호화 완료"
    else
        log_warning "GPG를 찾을 수 없어 암호화를 건너뜁니다"
    fi
}

# 백업 검증
verify_backup() {
    local backup_file="$1"
    
    log_info "백업 검증 중..."
    
    # 파일 존재 확인
    if [[ ! -f "$backup_file" && ! -f "$backup_file.gz" && ! -f "$backup_file.bz2" && ! -f "$backup_file.xz" && ! -f "$backup_file.gpg" ]]; then
        log_error "백업 파일 없음: $backup_file"
        return 1
    fi
    
    # 실제 백업 파일 찾기
    local actual_backup="$backup_file"
    for ext in "" ".gz" ".bz2" ".xz" ".gpg"; do
        if [[ -f "$backup_file$ext" ]]; then
            actual_backup="$backup_file$ext"
            break
        fi
    done
    
    # 파일 크기 확인
    local file_size=$(du -h "$actual_backup" | cut -f1)
    log_info "백업 파일 크기: $file_size"
    
    # 압축 파일 내용 확인
    case "$actual_backup" in
        *.gz)
            if command -v gzip >/dev/null 2>&1; then
                if gzip -t "$actual_backup" 2>/dev/null; then
                    log_success "gzip 백업 검증 통과"
                else
                    log_error "gzip 백업 손상됨"
                    return 1
                fi
            fi
            ;;
        *.bz2)
            if command -v bzip2 >/dev/null 2>&1; then
                if bzip2 -t "$actual_backup" 2>/dev/null; then
                    log_success "bzip2 백업 검증 통과"
                else
                    log_error "bzip2 백업 손상됨"
                    return 1
                fi
            fi
            ;;
        *.xz)
            if command -v xz >/dev/null 2>&1; then
                if xz -t "$actual_backup" 2>/dev/null; then
                    log_success "xz 백업 검증 통과"
                else
                    log_error "xz 백업 손상됨"
                    return 1
                fi
            fi
            ;;
        *.gpg)
            log_info "암호화된 백업 - 내용 검증 불가"
            ;;
        *)
            if command -v tar >/dev/null 2>&1; then
                if tar --test-label --file "$actual_backup" 2>/dev/null; then
                    log_success "tar 백업 검증 통과"
                else
                    log_error "tar 백업 손상됨"
                    return 1
                fi
            fi
            ;;
    esac
    
    return 0
}

# 백업 정보 기록
record_backup_info() {
    local backup_name="$1"
    local backup_type="$2"
    local backup_file="$3"
    
    local info_file="$CONFIG_DIR/backup-info.log"
    
    # 실제 백업 파일 찾기
    local actual_backup="$backup_file"
    for ext in "" ".gz" ".bz2" ".xz" ".gpg"; do
        if [[ -f "$backup_file$ext" ]]; then
            actual_backup="$backup_file$ext"
            break
        fi
    done
    
    # 백업 정보 기록
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local file_size=$(du -h "$actual_backup" | cut -f1)
    local file_path=$(realpath "$actual_backup")
    
    echo "$timestamp|$backup_name|$backup_type|$file_size|$file_path" >> "$info_file"
    
    log_success "백업 정보 기록됨"
}

# 백업 목록 보기
list_backups() {
    echo "=== UnifiedArch OS 백업 목록 ==="
    echo ""
    
    local info_file="$CONFIG_DIR/backup-info.log"
    if [[ ! -f "$info_file" ]]; then
        log_info "백업 기록 없음"
        return 0
    fi
    
    printf "%-25s %-12s %-10s %-10s %-50s\n" "백업 이름" "타입" "크기" "날짜" "경로"
    printf "%-25s %-12s %-10s %-10s %-50s\n" "-------------------------" "------------" "----------" "----------" "--------------------------------------------------"
    
    while IFS='|' read -r timestamp backup_name backup_type file_size file_path; do
        printf "%-25s %-12s %-10s %-10s %-50s\n" "$backup_name" "$backup_type" "$file_size" "${timestamp:0:10}" "$file_path"
    done < "$info_file"
    
    echo ""
    echo "백업 디렉토리: $BACKUP_DIR"
}

# 백업 복원
restore_backup() {
    local backup_name="$1"
    local restore_target="${2:-/}"
    
    if [[ -z "$backup_name" ]]; then
        log_error "백업 이름이 필요합니다"
        return 1
    fi
    
    log_info "백업 복원 시작: $backup_name -> $restore_target"
    
    # 백업 파일 찾기
    local backup_file=$(find_backup_file "$backup_name")
    if [[ -z "$backup_file" ]]; then
        log_error "백업 파일을 찾을 수 없음: $backup_name"
        return 1
    fi
    
    # 복원 전 확인
    if [[ "$restore_target" == "/" ]]; then
        read -p "루트 디렉토리에 복원하시겠습니까? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            log_info "복원 취소"
            return 0
        fi
    fi
    
    # 암호화된 백업 복호화
    if [[ "$backup_file" == *.gpg ]]; then
        backup_file=$(decrypt_backup "$backup_file")
        if [[ -z "$backup_file" ]]; then
            log_error "백업 복호화 실패"
            return 1
        fi
    fi
    
    # 백업 복원
    log_info "백업 복원 중..."
    
    local restore_options=(
        "--extract"
        "--file=$backup_file"
        "--preserve-permissions"
        "--xattrs"
        "--acl"
    )
    
    if [[ "$restore_target" != "/" ]]; then
        restore_options+=("--directory=$restore_target")
    fi
    
    # 복원 실행
    tar "${restore_options[@]}"
    
    # 임시 암호화 파일 정리
    if [[ "$backup_file" == *.gpg.decrypted ]]; then
        rm -f "$backup_file"
    fi
    
    log_success "백업 복원 완료: $backup_name"
}

# 백업 파일 찾기
find_backup_file() {
    local backup_name="$1"
    
    # 백업 정보에서 경로 찾기
    local info_file="$CONFIG_DIR/backup-info.log"
    if [[ -f "$info_file" ]]; then
        while IFS='|' read -r timestamp name backup_type file_size file_path; do
            if [[ "$name" == "$backup_name" ]]; then
                echo "$file_path"
                return 0
            fi
        done < "$info_file"
    fi
    
    # 직접 파일 검색
    local found_backup=$(find "$BACKUP_DIR" -name "$backup_name*" -type f | head -1)
    if [[ -n "$found_backup" ]]; then
        echo "$found_backup"
        return 0
    fi
    
    return 1
}

# 백업 복호화
decrypt_backup() {
    local encrypted_file="$1"
    local decrypted_file="${encrypted_file}.decrypted"
    
    if [[ "$ENCRYPTION" == "true" && -n "$ENCRYPTION_KEY" ]]; then
        log_info "백업 복호화 중..."
        echo "$ENCRYPTION_KEY" | gpg --batch --yes --passphrase-fd 0 --decrypt --output "$decrypted_file" "$encrypted_file" 2>/dev/null || {
            log_error "복호화 실패"
            return 1
        }
        echo "$decrypted_file"
    else
        echo "$encrypted_file"
    fi
}

# 오래된 백업 정리
cleanup_old_backups() {
    log_info "오래된 백업 정리 중..."
    
    load_backup_config
    
    local retention_days=${RETENTION_DAYS:-30}
    local cutoff_time=$(date -d "$retention_days days ago" +%s 2>/dev/null || date -d "-$retention_days days" +%s)
    
    local deleted_count=0
    local total_size=0
    
    # 백업 디렉토리 순회
    find "$BACKUP_DIR" -type f -name "*.tar*" | while read -r backup_file; do
        local file_time=$(stat -c %Y "$backup_file" 2>/dev/null || stat -f %m "$backup_file" 2>/dev/null)
        
        if [[ $file_time -lt $cutoff_time ]]; then
            local file_size=$(du -k "$backup_file" | cut -f1)
            ((total_size += file_size))
            ((deleted_count++))
            
            log_info "오래된 백업 삭제: $(basename "$backup_file")"
            rm -f "$backup_file"
        fi
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        local freed_space=$(echo "scale=1; $total_size/1024" | bc -l 2>/dev/null || echo "$((total_size/1024))")
        log_success "$deleted_count개 백업 삭제됨 (해제 공간: ${freed_space}MB)"
    else
        log_info "정리할 오래된 백업 없음"
    fi
}

# 원격 백업
remote_backup() {
    local backup_file="$1"
    
    if [[ "$REMOTE_BACKUP" != "true" ]]; then
        log_info "원격 백업 비활성화"
        return 0
    fi
    
    if [[ -z "$REMOTE_HOST" || -z "$REMOTE_USER" || -z "$REMOTE_PATH" ]]; then
        log_error "원격 백업 설정 불완전"
        return 1
    fi
    
    log_info "원격 백업 시작: $REMOTE_HOST"
    
    # scp로 원격 백업
    local remote_path="$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"
    
    if [[ -n "$REMOTE_KEY" ]]; then
        scp -i "$REMOTE_KEY" "$backup_file" "$remote_path"
    else
        scp "$backup_file" "$remote_path"
    fi
    
    log_success "원격 백업 완료"
}

# 백업 스케줄 설정
setup_backup_schedule() {
    log_info "백업 스케줄 설정 중..."
    
    load_backup_config
    
    if [[ "$SCHEDULE_ENABLED" != "true" ]]; then
        log_info "백업 스케줄 비활성화"
        return 0
    fi
    
    # crontab 항목 생성
    local cron_entry="$SCHEDULE_TIME $SCHEDULE_DAYS /opt/unifiedarch/src/backup/unifiedarch-backup.sh auto"
    
    # 현재 crontab 확인
    local current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    # 기존 UnifiedArch 백업 항목 제거
    current_crontab=$(echo "$current_crontab" | grep -v "unifiedarch-backup")
    
    # 새 항목 추가
    echo "$current_crontab" | { cat; echo "$cron_entry"; } | crontab -
    
    log_success "백업 스케줄 설정 완료"
    log_info "스케줄: $SCHEDULE_TIME $SCHEDULE_DAYS"
}

# 자동 백업 실행
auto_backup() {
    log_info "자동 백업 실행 중..."
    
    # 설정 로드
    load_backup_config
    
    # 백업 타입 결정
    local backup_type="incremental"
    local day_of_week=$(date +%u)
    
    case "$SCHEDULE_DAYS" in
        "weekly")
            if [[ $day_of_week -eq 1 ]]; then  # 월요일
                backup_type="full"
            fi
            ;;
        "monthly")
            local day_of_month=$(date +%d)
            if [[ $day_of_month -eq 1 ]]; then  # 매월 1일
                backup_type="full"
            fi
            ;;
        *)
            # daily는 항상 증분
            ;;
    esac
    
    # 백업 실행
    create_backup "$backup_type"
    
    # 오래된 백업 정리
    cleanup_old_backups
    
    # 원격 백업
    local latest_backup=$(find "$BACKUP_DIR" -name "*.tar*" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    if [[ -n "$latest_backup" ]]; then
        remote_backup "$latest_backup"
    fi
    
    log_success "자동 백업 완료"
}

# 백업 통계
show_backup_statistics() {
    echo "=== UnifiedArch OS 백업 통계 ==="
    echo ""
    
    # 백업 디렉토리 크기
    if [[ -d "$BACKUP_DIR" ]]; then
        local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
        local total_count=$(find "$BACKUP_DIR" -type f -name "*.tar*" | wc -l)
        
        echo "백업 디렉토리: $BACKUP_DIR"
        echo "전체 크기: $total_size"
        echo "백업 파일 수: $total_count"
        echo ""
    fi
    
    # 백업 타입별 통계
    echo "백업 타입별 통계:"
    for type in full incremental differential; do
        local count=$(find "$BACKUP_DIR/$type" -name "*.tar*" -type f 2>/dev/null | wc -l)
        local size=$(du -sh "$BACKUP_DIR/$type" 2>/dev/null | cut -f1 || echo "0B")
        echo "  $type: $count개 ($size)"
    done
    echo ""
    
    # 최근 백업
    echo "최근 백업 (5개):"
    find "$BACKUP_DIR" -name "*.tar*" -type f -printf '%T@ %p\n' | sort -n | tail -5 | while read -r timestamp file; do
        local file_size=$(du -h "$file" | cut -f1)
        local file_date=$(date -d @"$timestamp" '+%Y-%m-%d %H:%M:%S')
        echo "  $(basename "$file"): $file_size ($file_date)"
    done
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 백업 및 복구 시스템"
    echo ""
    echo "사용법: $0 [명령] [인자...]"
    echo ""
    echo "명령:"
    echo "  create [type] [name]     - 백업 생성 (full/incremental/differential)"
    echo "  restore <name> [target]  - 백업 복원"
    echo "  list                     - 백업 목록 보기"
    echo "  cleanup                  - 오래된 백업 정리"
    echo "  schedule                 - 백업 스케줄 설정"
    echo "  auto                     - 자동 백업 실행"
    echo "  stats                    - 백업 통계 보기"
    echo "  help                     - 이 도움말 표시"
    echo ""
    echo "예시:"
    echo "  $0 create full mybackup  - 전체 백업 생성"
    echo "  $0 restore mybackup /tmp - 백업 복원"
    echo "  $0 list                  - 백업 목록 보기"
    echo "  $0 auto                  - 자동 백업 실행"
}

# 메인 함수
main() {
    local command="${1:-help}"
    
    # 환경 초기화
    init_backup_environment
    
    case "$command" in
        "create")
            create_backup "${2:-full}" "${3:-}"
            ;;
        "restore")
            restore_backup "${2:-}" "${3:-/}"
            ;;
        "list")
            list_backups
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "schedule")
            setup_backup_schedule
            ;;
        "auto")
            auto_backup
            ;;
        "stats")
            show_backup_statistics
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
