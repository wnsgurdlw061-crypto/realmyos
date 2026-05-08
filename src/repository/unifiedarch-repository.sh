#!/bin/bash
#
# UnifiedArch OS 패키지 저장소 및 미러 정책
# 패키지 저장소 관리 및 미러 정책
#
# 기능:
# - 패키지 저장소 설정
# - 미러 자동 선택
# - 저장소 동기화
# - 패키지 캐시 관리
#

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
REPOSITORY_DIR="/var/lib/unifiedarch/repository"
CONFIG_DIR="/etc/unifiedarch/repository"
LOG_FILE="/var/log/unifiedarch-repository.log"

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
log_repository() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] REPOSITORY: $1" >> "$LOG_FILE"
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
    mkdir -p "$REPOSITORY_DIR" "$CONFIG_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# 기본 저장소 설정
setup_base_repositories() {
    log_step "기본 저장소 설정 중..."
    
    # pacman.conf 설정
    cat > /etc/pacman.conf << 'EOF'
#
# /etc/pacman.conf
# UnifiedArch OS 패키지 관리자 설정
#

[options]
# 기본 설정
HoldPkg     = pacman glibc
Architecture = auto

# 로그 설정
LogFile     = /var/log/pacman.log
GPGDir      = /etc/pacman.d/gnupg/
CheckSpace

# 캐시 설정
CacheDir    = /var/cache/pacman/pkg/
CacheDir    = /var/lib/unifiedarch/repository/cache/

# 색상 출력
Color
TotalDownload

# 상세 출력
VerbosePkgLists

# 병렬 다운로드
ParallelDownloads = 5

# 리포지토리 설정
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

# UnifiedArch OS 공식 저장소
[unifiedarch-core]
Server = https://repo.unifiedarch.org/core/$arch
Server = https://mirror1.unifiedarch.org/core/$arch
Server = https://mirror2.unifiedarch.org/core/$arch

[unifiedarch-extra]
Server = https://repo.unifiedarch.org/extra/$arch
Server = https://mirror1.unifiedarch.org/extra/$arch
Server = https://mirror2.unifiedarch.org/extra/$arch

[unifiedarch-community]
Server = https://repo.unifiedarch.org/community/$arch
Server = https://mirror1.unifiedarch.org/community/$arch
Server = https://mirror2.unifiedarch.org/community/$arch

# Arch Linux 호환 저장소 (필요시)
[core]
Server = https://archlinux.org/core/os/$arch/
Server = https://mirror.funami.tech/archlinux/core/os/$arch/

[extra]
Server = https://archlinux.org/extra/os/$arch/
Server = https://mirror.funami.tech/archlinux/extra/os/$arch/

[community]
Server = https://archlinux.org/community/os/$arch/
Server = https://mirror.funami.tech/archlinux/community/os/$arch/

# 멀티리브 저장소
[multilib]
Server = https://archlinux.org/multilib/os/$arch/
Server = https://mirror.funami.tech/archlinux/multilib/os/$arch/

# 테스트 저장소 (개발용)
[unifiedarch-testing]
Server = https://repo.unifiedarch.org/testing/$arch
Server = https://mirror1.unifiedarch.org/testing/$arch
SigLevel = PackageOptional

# AUR 저장소 (선택적)
[aur]
Server = https://aur.unifiedarch.org/$arch
SigLevel = Never
EOF
    
    log_success "기본 저장소 설정 완료"
    log_repository "기본 저장소 설정 완료"
}

# 미러 목록 생성
create_mirror_list() {
    log_step "미러 목록 생성 중..."
    
    cat > "$CONFIG_DIR/mirrors.conf" << 'EOF'
# UnifiedArch OS 미러 목록
# 형식: 국가|URL|위도|경도|속도|신뢰도

# 한국
South Korea|https://mirror1.unifiedarch.org|37.5665|126.9780|100|95
South Korea|https://mirror2.unifiedarch.org|37.5665|126.9780|95|90
South Korea|https://kr.archive.unifiedarch.org|37.5665|126.9780|90|85

# 일본
Japan|https://jp.archive.unifiedarch.org|35.6762|139.6503|95|90
Japan|https://mirror3.unifiedarch.org|35.6762|139.6503|90|85

# 미국
United States|https://us.archive.unifiedarch.org|40.7128|-74.0060|85|80
United States|https://mirror4.unifiedarch.org|40.7128|-74.0060|80|75

# 독일
Germany|https://de.archive.unifiedarch.org|52.5200|13.4050|90|85
Germany|https://mirror5.unifiedarch.org|52.5200|13.4050|85|80

# 영국
United Kingdom|https://uk.archive.unifiedarch.org|51.5074|-0.1278|85|80
United Kingdom|https://mirror6.unifiedarch.org|51.5074|-0.1278|80|75

# 프랑스
France|https://fr.archive.unifiedarch.org|48.8566|2.3522|80|75
France|https://mirror7.unifiedarch.org|48.8566|2.3522|75|70

# 중국
China|https://cn.archive.unifiedarch.org|39.9042|116.4074|85|80
China|https://mirror8.unifiedarch.org|39.9042|116.4074|80|75

# 호주
Australia|https://au.archive.unifiedarch.org|-33.8688|151.2093|75|70
Australia|https://mirror9.unifiedarch.org|-33.8688|151.2093|70|65

# 캐나다
Canada|https://ca.archive.unifiedarch.org|45.4215|-75.6972|80|75
Canada|https://mirror10.unifiedarch.org|45.4215|-75.6972|75|70

# 인도
India|https://in.archive.unifiedarch.org|28.6139|77.2090|75|70
India|https://mirror11.unifiedarch.org|28.6139|77.2090|70|65

# 브라질
Brazil|https://br.archive.unifiedarch.org|-23.5505|-46.6333|70|65
Brazil|https://mirror12.unifiedarch.org|-23.5505|-46.6333|65|60

# 러시아
Russia|https://ru.archive.unifiedarch.org|55.7558|37.6173|75|70
Russia|https://mirror13.unifiedarch.org|55.7558|37.6173|70|65

# 남아프리카
South Africa|https://za.archive.unifiedarch.org|-26.2041|28.0473|65|60
South Africa|https://mirror14.unifiedarch.org|-26.2041|28.0473|60|55
EOF
    
    log_success "미러 목록 생성 완료"
    log_repository "미러 목록 생성"
}

# 지리적 위치 기반 미러 선택
select_geographic_mirrors() {
    log_step "지리적 위치 기반 미러 선택 중..."
    
    # 사용자 위치 확인 (IP 기반)
    local user_location=""
    if command -v curl &>/dev/null; then
        user_location=$(curl -s "http://ip-api.com/json" | grep -o '"country":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    fi
    
    if [[ -z "$user_location" ]]; then
        log_warning "사용자 위치 확인 실패, 기본 미러 사용"
        user_location="South Korea"
    fi
    
    log_info "감지된 위치: $user_location"
    
    # 해당 국가 미러 선택
    local selected_mirrors=()
    while IFS= read -r line; do
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            local country=$(echo "$line" | cut -d'|' -f1)
            local url=$(echo "$line" | cut -d'|' -f2)
            local speed=$(echo "$line" | cut -d'|' -f5)
            local reliability=$(echo "$line" | cut -d'|' -f6)
            
            if [[ "$country" == "$user_location" ]]; then
                selected_mirrors+=("$url:$speed:$reliability")
            fi
        fi
    done < "$CONFIG_DIR/mirrors.conf"
    
    # 속도와 신뢰도 기반 정렬
    IFS=$'\n' selected_mirrors=($(sort -t: -k2 -nr -k3 -nr <<<"${selected_mirrors[*]}"))
    unset IFS
    
    if [[ ${#selected_mirrors[@]} -eq 0 ]]; then
        log_warning "해당 국가 미러 없음, 전체 미러에서 선택"
        # 전체 미러에서 상위 5개 선택
        while IFS= read -r line; do
            if [[ -n "$line" && ! "$line" =~ ^# ]]; then
                local url=$(echo "$line" | cut -d'|' -f2)
                local speed=$(echo "$line" | cut -d'|' -f5)
                local reliability=$(echo "$line" | cut -d'|' -f6)
                selected_mirrors+=("$url:$speed:$reliability")
            fi
        done < "$CONFIG_DIR/mirrors.conf"
        
        IFS=$'\n' selected_mirrors=($(sort -t: -k2 -nr -k3 -nr <<<"${selected_mirrors[*]}"))
        unset IFS
    fi
    
    # 상위 5개 미러 선택
    local final_mirrors=()
    for i in {0..4}; do
        if [[ $i -lt ${#selected_mirrors[@]} ]]; then
            local mirror=$(echo "${selected_mirrors[$i]}" | cut -d: -f1)
            final_mirrors+=("$mirror")
        fi
    done
    
    # pacman.conf 업데이트
    if [[ ${#final_mirrors[@]} -gt 0 ]]; then
        log_info "선택된 미러:"
        for mirror in "${final_mirrors[@]}"; do
            log_info "  - $mirror"
        done
        
        # 미러 목록 파일 생성
        cat > /etc/pacman.d/mirrorlist.unifiedarch << EOF
# UnifiedArch OS 자동 생성 미러 목록
# 생성 시간: $(date '+%Y-%m-%d %H:%M:%S')
# 사용자 위치: $user_location

# 선택된 미러
EOF
        
        for mirror in "${final_mirrors[@]}"; do
            echo "Server = $mirror" >> /etc/pacman.d/mirrorlist.unifiedarch
        done
        
        log_success "지리적 미러 선택 완료: ${#final_mirrors[@]}개 미러"
        log_repository "지리적 미러 선택: $user_location, ${#final_mirrors[@]}개 미러"
    else
        log_error "선택 가능한 미러 없음"
        return 1
    fi
}

# 미러 속도 테스트
test_mirror_speeds() {
    log_step "미러 속도 테스트 중..."
    
    local test_file="core.db.sig"
    local mirror_speeds=()
    
    # 미러 목록에서 속도 테스트
    while IFS= read -r line; do
        if [[ "$line" =~ ^Server = ]]; then
            local mirror_url=$(echo "$line" | sed 's/Server = //')
            local full_url="$mirror_url/$test_file"
            
            log_info "테스트 중: $mirror_url"
            
            # 속도 테스트
            if command -v curl &>/dev/null; then
                local start_time=$(date +%s.%N)
                if curl -s --max-time 10 --connect-timeout 5 "$full_url" >/dev/null 2>&1; then
                    local end_time=$(date +%s.%N)
                    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "999")
                    mirror_speeds+=("$duration:$mirror_url")
                    log_info "  속도: ${duration}초"
                else
                    mirror_speeds+=("999:$mirror_url")
                    log_info "  실패"
                fi
            else
                mirror_speeds+=("999:$mirror_url")
                log_info "  curl 없음"
            fi
        fi
    done < /etc/pacman.d/mirrorlist.unifiedarch
    
    # 속도 기반 정렬
    IFS=$'\n' mirror_speeds=($(sort -n <<<"${mirror_speeds[*]}"))
    unset IFS
    
    # 최적 미러 목록 생성
    cat > /etc/pacman.d/mirrorlist.optimized << EOF
# UnifiedArch OS 최적화 미러 목록
# 생성 시간: $(date '+%Y-%m-%d %H:%M:%S')
# 속도 테스트 기반 정렬

EOF
    
    for speed_info in "${mirror_speeds[@]}"; do
        local speed=$(echo "$speed_info" | cut -d: -f1)
        local mirror_url=$(echo "$speed_info" | cut -d: -f2)
        
        if [[ "$speed" != "999" ]]; then
            echo "Server = $mirror_url" >> /etc/pacman.d/mirrorlist.optimized
            log_info "최적 미러 추가: $mirror_url (${speed}초)"
        fi
    done
    
    # pacman.conf 업데이트
    sed -i 's|Server = .*|Server = file:///etc/pacman.d/mirrorlist.optimized|' /etc/pacman.conf
    
    log_success "미러 속도 테스트 완료"
    log_repository "미러 속도 테스트 완료"
}

# 저장소 동기화
sync_repositories() {
    log_step "저장소 동기화 중..."
    
    # 패키지 데이터베이스 동기화
    if pacman -Sy --noconfirm 2>/dev/null; then
        log_success "패키지 데이터베이스 동기화 완료"
        log_repository "패키지 데이터베이스 동기화 완료"
    else
        log_error "패키지 데이터베이스 동기화 실패"
        return 1
    fi
    
    # GPG 키 업데이트
    if pacman-key --init 2>/dev/null && pacman-key --populate 2>/dev/null; then
        log_success "GPG 키 업데이트 완료"
        log_repository "GPG 키 업데이트 완료"
    else
        log_warning "GPG 키 업데이트 실패"
    fi
}

# 패키지 캐시 관리
manage_package_cache() {
    log_step "패키지 캐시 관리 중..."
    
    # 캐시 디렉토리 확인
    local cache_dirs=(
        "/var/cache/pacman/pkg/"
        "/var/lib/unifiedarch/repository/cache/"
    )
    
    local total_size=0
    for cache_dir in "${cache_dirs[@]}"; do
        if [[ -d "$cache_dir" ]]; then
            local dir_size=$(du -sb "$cache_dir" 2>/dev/null | cut -f1 || echo "0")
            total_size=$((total_size + dir_size))
        fi
    done
    
    local cache_size_gb=$((total_size / 1024 / 1024 / 1024))
    log_info "현재 캐시 크기: ${cache_size_gb}GB"
    
    # 캐시 정리 정책
    local max_cache_gb=5
    if [[ $cache_size_gb -gt $max_cache_gb ]]; then
        log_info "캐시 정리 필요 (최대 ${max_cache_gb}GB)"
        
        # 오래된 패키지 정리
        for cache_dir in "${cache_dirs[@]}"; do
            if [[ -d "$cache_dir" ]]; then
                # 30일 이상 된 패키지 정리
                find "$cache_dir" -name "*.pkg.tar*" -mtime +30 -delete 2>/dev/null || true
                
                # 사용하지 않는 패키지 정리
                find "$cache_dir" -name "*.pkg.tar.*" -type f -exec bash -c '
                    pkgname=$(basename "$1" | sed "s/-[0-9].*//")
                    if ! pacman -Q "$pkgname" &>/dev/null; then
                        rm "$1"
                    fi
                ' _ {} \; 2>/dev/null || true
            fi
        done
        
        # 정리 후 크기 확인
        local new_total_size=0
        for cache_dir in "${cache_dirs[@]}"; do
            if [[ -d "$cache_dir" ]]; then
                local dir_size=$(du -sb "$cache_dir" 2>/dev/null | cut -f1 || echo "0")
                new_total_size=$((new_total_size + dir_size))
            fi
        done
        
        local new_cache_size_gb=$((new_total_size / 1024 / 1024 / 1024))
        log_success "캐시 정리 완료: ${cache_size_gb}GB → ${new_cache_size_gb}GB"
        log_repository "캐시 정리: ${cache_size_gb}GB → ${new_cache_size_gb}GB"
    else
        log_info "캐시 정리 불필요"
    fi
}

# 저장소 상태 확인
check_repository_status() {
    log_step "저장소 상태 확인 중..."
    
    echo "저장소 상태 보고"
    echo "=================="
    echo ""
    
    # 미러 상태 확인
    echo "미러 상태:"
    local mirror_count=0
    local working_mirrors=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^Server = ]]; then
            mirror_count=$((mirror_count + 1))
            local mirror_url=$(echo "$line" | sed 's/Server = //')
            
            # 미러 연결 테스트
            if curl -s --max-time 5 --connect-timeout 3 "$mirror_url" >/dev/null 2>&1; then
                echo "  ✓ $mirror_url"
                working_mirrors=$((working_mirrors + 1))
            else
                echo "  ✗ $mirror_url"
            fi
        fi
    done < /etc/pacman.d/mirrorlist.optimized
    
    echo ""
    echo "미러 통계: $working_mirrors/$mirror_count 작동 중"
    echo ""
    
    # 패키지 데이터베이스 상태
    echo "패키지 데이터베이스 상태:"
    local db_files=(
        "/var/lib/pacman/sync/unifiedarch-core.db"
        "/var/lib/pacman/sync/unifiedarch-extra.db"
        "/var/lib/pacman/sync/unifiedarch-community.db"
    )
    
    for db_file in "${db_files[@]}"; do
        local db_name=$(basename "$db_file")
        if [[ -f "$db_file" ]]; then
            local db_size=$(stat -c%s "$db_file" 2>/dev/null || echo "0")
            local db_date=$(stat -c%Y "$db_file" 2>/dev/null || echo "0")
            local db_date_str=$(date -d "@$db_date" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "알 수 없음")
            
            echo "  $db_name: $(du -h "$db_file" 2>/dev/null | cut -f1) ($db_date_str)"
        else
            echo "  $db_name: 없음"
        fi
    done
    
    echo ""
    
    # 캐시 상태
    echo "캐시 상태:"
    local cache_dirs=(
        "/var/cache/pacman/pkg/"
        "/var/lib/unifiedarch/repository/cache/"
    )
    
    for cache_dir in "${cache_dirs[@]}"; do
        if [[ -d "$cache_dir" ]]; then
            local cache_size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1 || echo "알 수 없음")
            local cache_count=$(find "$cache_dir" -name "*.pkg.tar.*" 2>/dev/null | wc -l)
            echo "  $cache_dir: $cache_size ($cache_count 패키지)"
        else
            echo "  $cache_dir: 없음"
        fi
    done
    
    echo ""
    
    # 마지막 동기화 시간
    echo "마지막 동기화:"
    local last_sync=$(stat -c%Y /var/lib/pacman/sync/unifiedarch-core.db 2>/dev/null || echo "0")
    if [[ $last_sync -gt 0 ]]; then
        local last_sync_str=$(date -d "@$last_sync" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "알 수 없음")
        echo "  $last_sync_str"
    else
        echo "  동기화 기록 없음"
    fi
    
    echo ""
    echo "=================="
    
    log_repository "저장소 상태 확인 완료"
}

# 자동 미러 업데이트 서비스
setup_auto_mirror_update() {
    log_step "자동 미러 업데이트 서비스 설정 중..."
    
    # systemd 서비스 생성
    cat > /etc/systemd/system/unifiedarch-mirror-update.service << 'EOF'
[Unit]
Description=UnifiedArch OS Auto Mirror Update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/unifiedarch-mirror-update
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
    
    # systemd 타이머 생성
    cat > /etc/systemd/system/unifiedarch-mirror-update.timer << 'EOF'
[Unit]
Description=UnifiedArch OS Auto Mirror Update Timer
Requires=unifiedarch-mirror-update.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF
    
    # 미러 업데이트 스크립트
    cat > /usr/local/bin/unifiedarch-mirror-update << 'EOF'
#!/bin/bash
# UnifiedArch OS 자동 미러 업데이트

LOG_FILE="/var/log/unifiedarch-repository.log"

log_mirror() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] AUTO-MIRROR: \$1" >> "\$LOG_FILE"
}

log_mirror "자동 미러 업데이트 시작"

# 미러 속도 테스트
if /usr/local/bin/unifiedarch-repository test-mirrors; then
    log_mirror "미러 속도 테스트 완료"
else
    log_mirror "미러 속도 테스트 실패"
    exit 1
fi

# 저장소 동기화
if pacman -Sy --noconfirm; then
    log_mirror "저장소 동기화 완료"
else
    log_mirror "저장소 동기화 실패"
    exit 1
fi

# 캐시 정리
if /usr/local/bin/unifiedarch-repository clean-cache; then
    log_mirror "캐시 정리 완료"
else
    log_mirror "캐시 정리 실패"
fi

log_mirror "자동 미러 업데이트 완료"
EOF
    
    chmod +x /usr/local/bin/unifiedarch-mirror-update
    
    # 서비스 활성화
    systemctl daemon-reload 2>/dev/null || log_warning "systemd 데몬 리로드 실패"
    systemctl enable unifiedarch-mirror-update.timer 2>/dev/null || log_warning "미러 업데이트 타이머 활성화 실패"
    systemctl start unifiedarch-mirror-update.timer 2>/dev/null || log_warning "미러 업데이트 타이머 시작 실패"
    
    log_success "자동 미러 업데이트 서비스 설정 완료"
    log_repository "자동 미러 업데이트 서비스 설정"
}

# 저장소 관리자 생성
create_repository_manager() {
    log_step "저장소 관리자 생성 중..."
    
    cat > /usr/local/bin/unifiedarch-repository << 'EOF'
#!/bin/bash
# UnifiedArch OS 저장소 관리자

REPOSITORY_DIR="/var/lib/unifiedarch/repository"
CONFIG_DIR="/etc/unifiedarch/repository"

show_help() {
    echo "UnifiedArch OS 저장소 관리자"
    echo ""
    echo "사용법: $0 [명령어] [인자]"
    echo ""
    echo "명령어:"
    echo "  setup              - 기본 저장소 설정"
    echo "  select-mirrors     - 미러 선택"
    echo "  test-mirrors       - 미러 속도 테스트"
    echo "  sync               - 저장소 동기화"
    echo "  clean-cache        - 패키지 캐시 정리"
    echo "  status             - 저장소 상태 확인"
    echo "  auto-update        - 자동 업데이트 설정"
    echo "  help               - 이 도움말"
}

setup_repositories() {
    echo "기본 저장소 설정 중..."
    
    # 기본 저장소 설정
    /usr/local/bin/unifiedarch-repository setup-base
    
    # 미러 목록 생성
    /usr/local/bin/unifiedarch-repository create-mirrors
    
    # 지리적 미러 선택
    /usr/local/bin/unifiedarch-repository select-geographic
    
    echo "기본 저장소 설정 완료"
}

select_mirrors() {
    echo "미러 선택 중..."
    /usr/local/bin/unifiedarch-repository select-geographic
    echo "미러 선택 완료"
}

test_mirrors() {
    echo "미러 속도 테스트 중..."
    /usr/local/bin/unifiedarch-repository test-speed
    echo "미러 속도 테스트 완료"
}

sync_repos() {
    echo "저장소 동기화 중..."
    pacman -Sy --noconfirm
    echo "저장소 동기화 완료"
}

clean_cache() {
    echo "패키지 캐시 정리 중..."
    /usr/local/bin/unifiedarch-repository manage-cache
    echo "패키지 캐시 정리 완료"
}

show_status() {
    echo "저장소 상태 확인 중..."
    /usr/local/bin/unifiedarch-repository check-status
}

setup_auto_update() {
    echo "자동 업데이트 설정 중..."
    /usr/local/bin/unifiedarch-repository setup-auto
    echo "자동 업데이트 설정 완료"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    case "$action" in
        setup)
            setup_repositories
            ;;
        select-mirrors)
            select_mirrors
            ;;
        test-mirrors)
            test_mirrors
            ;;
        sync)
            sync_repos
            ;;
        clean-cache)
            clean_cache
            ;;
        status)
            show_status
            ;;
        auto-update)
            setup_auto_update
            ;;
        help)
            show_help
            ;;
        *)
            echo "알 수 없는 명령어: $action"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
EOF
    
    chmod +x /usr/local/bin/unifiedarch-repository
    
    log_success "저장소 관리자 생성 완료"
    log_repository "저장소 관리자 생성"
}

# 도움말
show_help() {
    echo "UnifiedArch OS 패키지 저장소 및 미러 정책"
    echo ""
    echo "사용법: $0 [명령어]"
    echo ""
    echo "명령어:"
    echo "  setup-base         - 기본 저장소 설정"
    echo "  create-mirrors     - 미러 목록 생성"
    echo "  select-geographic  - 지리적 미러 선택"
    echo "  test-mirrors       - 미러 속도 테스트"
    echo "  sync-repositories  - 저장소 동기화"
    echo "  manage-cache       - 패키지 캐시 관리"
    echo "  check-status       - 저장소 상태 확인"
    echo "  setup-auto         - 자동 업데이트 설정"
    echo "  create-manager     - 저장소 관리자 생성"
    echo "  setup-all           - 전체 저장소 설정"
    echo "  help               - 이 도움말"
    echo ""
    echo "기능:"
    echo "  - 패키지 저장소 설정"
    echo "  - 지리적 위치 기반 미러 자동 선택"
    echo "  - 미러 속도 테스트 및 최적화"
    echo "  - 저장소 동기화"
    echo "  - 패키지 캐시 관리"
    echo "  - 자동 업데이트 서비스"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    check_root
    create_directories
    
    case "$action" in
        setup-base)
            setup_base_repositories
            ;;
        create-mirrors)
            create_mirror_list
            ;;
        select-geographic)
            select_geographic_mirrors
            ;;
        test-mirrors)
            test_mirror_speeds
            ;;
        sync-repositories)
            sync_repositories
            ;;
        manage-cache)
            manage_package_cache
            ;;
        check-status)
            check_repository_status
            ;;
        setup-auto)
            setup_auto_mirror_update
            ;;
        create-manager)
            create_repository_manager
            ;;
        setup-all)
            setup_base_repositories
            create_mirror_list
            select_geographic_mirrors
            test_mirror_speeds
            sync_repositories
            manage_package_cache
            setup_auto_mirror_update
            create_repository_manager
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
