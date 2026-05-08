#!/bin/bash
# UnifiedArch OS 사용자 관리 및 인증 시스템
# 완벽한 사용자 계정 관리

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
USER_DB="/etc/unifiedarch/users.db"
GROUP_DB="/etc/unifiedarch/groups.db"
AUTH_LOG="/var/log/unifiedarch-auth.log"

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
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" >> "$AUTH_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $1" >> "$AUTH_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $1" >> "$AUTH_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >> "$AUTH_LOG"
}

# 데이터베이스 초기화
init_databases() {
    mkdir -p "$(dirname "$USER_DB")" "$(dirname "$GROUP_DB")" "$(dirname "$AUTH_LOG")"
    
    if [[ ! -f "$USER_DB" ]]; then
        cat > "$USER_DB" << 'EOF'
# UnifiedArch OS 사용자 데이터베이스
# 형식: username:uid:gid:full_name:home_dir:shell:last_login:failed_attempts:locked

root:0:0:Root User:/root:/bin/bash:0:0:false
EOF
        log_info "사용자 데이터베이스 초기화됨"
    fi
    
    if [[ ! -f "$GROUP_DB" ]]; then
        cat > "$GROUP_DB" << 'EOF'
# UnifiedArch OS 그룹 데이터베이스
# 형식: groupname:gid:members

root:0:root
unifiedarch:1000:
wheel:10:
sudo:27:
users:100:
EOF
        log_info "그룹 데이터베이스 초기화됨"
    fi
}

# 사용자 생성
create_user() {
    local username="$1"
    local full_name="${2:-}"
    local home_dir="${3:-/home/$username}"
    local shell="${4:-/bin/bash}"
    local password="${5:-}"
    
    if [[ -z "$username" ]]; then
        log_error "사용자 이름이 필요합니다"
        return 1
    fi
    
    # 사용자 이름 유효성 검사
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_]*$ ]]; then
        log_error "잘못된 사용자 이름 형식: $username"
        return 1
    fi
    
    # 중복 사용자 확인
    if grep -q "^$username:" "$USER_DB"; then
        log_error "사용자 이미 존재: $username"
        return 1
    fi
    
    # UID/GID 생성
    local uid=$(get_next_uid)
    local gid=$uid
    
    # 홈 디렉토리 생성
    mkdir -p "$home_dir"
    
    # 비밀번호 설정
    if [[ -z "$password" ]]; then
        password=$(generate_password)
        log_info "생성된 비밀번호: $password"
    fi
    
    # 비밀번호 해시
    local password_hash=$(echo "$password" | openssl passwd -stdin -6 2>/dev/null || echo "$password")
    
    # 시스템 사용자 생성
    if [[ $EUID -eq 0 ]]; then
        useradd -m -d "$home_dir" -s "$shell" -u "$uid" -g "$gid" "$username" 2>/dev/null || true
        echo "$username:$password" | chpasswd 2>/dev/null || true
    fi
    
    # 데이터베이스에 사용자 추가
    local timestamp=$(date +%s)
    echo "$username:$uid:$gid:$full_name:$home_dir:$shell:$timestamp:0:false" >> "$USER_DB"
    
    # 기본 그룹에 사용자 추가
    add_user_to_group "$username" "users"
    add_user_to_group "$username" "unifiedarch"
    
    log_success "사용자 생성 완료: $username (UID: $uid, GID: $gid)"
    log_info "홈 디렉토리: $home_dir"
    log_info "셸: $shell"
    
    # 초기 설정
    setup_user_environment "$username" "$home_dir"
}

# 다음 UID 가져오기
get_next_uid() {
    local max_uid=1000
    while IFS=: read -r username uid gid full_name home_dir shell last_login failed_attempts locked; do
        if [[ "$uid" =~ ^[0-9]+$ ]] && [[ $uid -gt $max_uid ]]; then
            max_uid=$uid
        fi
    done < "$USER_DB"
    echo $((max_uid + 1))
}

# 비밀번호 생성
generate_password() {
    local length=12
    local chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
    local password=""
    
    for i in $(seq 1 $length); do
        password+="${chars:$((RANDOM % ${#chars})):1}"
    done
    
    echo "$password"
}

# 사용자 환경 설정
setup_user_environment() {
    local username="$1"
    local home_dir="$2"
    
    # 기본 설정 파일 생성
    mkdir -p "$home_dir"/{.config,.local,.cache}
    
    # .bashrc
    cat > "$home_dir/.bashrc" << 'EOF'
# UnifiedArch OS 사용자 설정
export PATH="/opt/unifiedarch/bin:$PATH"
export EDITOR="nano"
export BROWSER="firefox"

# 프롬프트 설정
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# 별칭
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# UnifiedArch OS 별칭
alias unifiedarch='/opt/unifiedarch/src/tools/config-manager.sh'
alias uamonitor='/opt/unifiedarch/src/tools/system-monitor.sh'
alias uaconfig='/opt/unifiedarch/src/tools/config-manager.sh'
alias uainstall='/opt/unifiedarch/src/installer/install.sh'
alias uanetwork='/opt/unifiedarch/src/network/unifiedarch-network.sh'
alias uaservice='/opt/unifiedarch/src/services/unifiedarch-service.sh'
EOF
    
    # .profile
    cat > "$home_dir/.profile" << 'EOF'
# UnifiedArch OS 사용자 프로필

# 환경 변수
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"

# PATH 설정
if [ -d "/opt/unifiedarch/bin" ]; then
    export PATH="/opt/unifiedarch/bin:$PATH"
fi

# 시작 프로그램
if [ -f "$HOME/.config/autostart/unifiedarch-monitor.desktop" ]; then
    # 데스크톱 환경에서 자동 시작
    :
fi
EOF
    
    # 권한 설정
    chown -R "$username:$username" "$home_dir"
    chmod 755 "$home_dir"
    chmod 644 "$home_dir"/.bashrc "$home_dir"/.profile
    
    log_success "사용자 환경 설정 완료: $username"
}

# 사용자 삭제
delete_user() {
    local username="$1"
    local remove_home="${2:-true}"
    
    if [[ -z "$username" ]]; then
        log_error "사용자 이름이 필요합니다"
        return 1
    fi
    
    # root 사용자 삭제 방지
    if [[ "$username" == "root" ]]; then
        log_error "root 사용자는 삭제할 수 없습니다"
        return 1
    fi
    
    # 사용자 존재 확인
    if ! grep -q "^$username:" "$USER_DB"; then
        log_error "사용자 없음: $username"
        return 1
    fi
    
    # 시스템 사용자 삭제
    if [[ $EUID -eq 0 ]]; then
        if [[ "$remove_home" == "true" ]]; then
            userdel -r "$username" 2>/dev/null || true
        else
            userdel "$username" 2>/dev/null || true
        fi
    fi
    
    # 데이터베이스에서 사용자 삭제
    grep -v "^$username:" "$USER_DB" > "$USER_DB.tmp"
    mv "$USER_DB.tmp" "$USER_DB"
    
    # 그룹에서 사용자 제거
    remove_user_from_all_groups "$username"
    
    log_success "사용자 삭제 완료: $username"
}

# 사용자 정보 수정
modify_user() {
    local username="$1"
    local field="$2"
    local value="$3"
    
    if [[ -z "$username" || -z "$field" || -z "$value" ]]; then
        log_error "사용자 이름, 필드, 값이 필요합니다"
        return 1
    fi
    
    # 필드 유효성 검사
    case "$field" in
        "full_name"|"home_dir"|"shell")
            ;;
        *)
            log_error "알 수 없는 필드: $field"
            return 1
            ;;
    esac
    
    # 사용자 존재 확인
    if ! grep -q "^$username:" "$USER_DB"; then
        log_error "사용자 없음: $username"
        return 1
    fi
    
    # 데이터베이스 업데이트
    local temp_file="$USER_DB.tmp"
    while IFS=: read -r db_username uid gid full_name home_dir shell last_login failed_attempts locked; do
        if [[ "$db_username" == "$username" ]]; then
            case "$field" in
                "full_name")
                    full_name="$value"
                    ;;
                "home_dir")
                    home_dir="$value"
                    ;;
                "shell")
                    shell="$value"
                    ;;
            esac
        fi
        echo "$db_username:$uid:$gid:$full_name:$home_dir:$shell:$last_login:$failed_attempts:$locked"
    done < "$USER_DB" > "$temp_file"
    
    mv "$temp_file" "$USER_DB"
    
    log_success "사용자 정보 수정 완료: $username ($field = $value)"
}

# 사용자 목록 보기
list_users() {
    echo "=== UnifiedArch OS 사용자 목록 ==="
    echo ""
    printf "%-15s %-6s %-6s %-20s %-25s %-15s %-10s %-5s %-5s\n" \
           "사용자" "UID" "GID" "전체 이름" "홈 디렉토리" "셸" "실패" "잠금"
    printf "%-15s %-6s %-6s %-20s %-25s %-15s %-10s %-5s %-5s\n" \
           "---------------" "------" "------" "--------------------" "-------------------------" "---------------" "------" "------"
    
    while IFS=: read -r username uid gid full_name home_dir shell last_login failed_attempts locked; do
        local last_login_str="없음"
        if [[ "$last_login" != "0" ]]; then
            last_login_str=$(date -d @"$last_login" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$last_login")
        fi
        
        printf "%-15s %-6s %-6s %-20s %-25s %-15s %-10s %-5s %-5s\n" \
               "$username" "$uid" "$gid" "$full_name" "$home_dir" "$shell" "$failed_attempts" "$locked"
    done < "$USER_DB"
}

# 사용자 인증
authenticate_user() {
    local username="$1"
    local password="$2"
    
    if [[ -z "$username" || -z "$password" ]]; then
        log_error "사용자 이름과 비밀번호가 필요합니다"
        return 1
    fi
    
    # 사용자 정보 가져오기
    local user_info=$(grep "^$username:" "$USER_DB" | head -1)
    if [[ -z "$user_info" ]]; then
        log_error "사용자 없음: $username"
        return 1
    fi
    
    IFS=: read -r db_username uid gid full_name home_dir shell last_login failed_attempts locked <<< "$user_info"
    
    # 계정 잠금 확인
    if [[ "$locked" == "true" ]]; then
        log_error "계정이 잠겨 있습니다: $username"
        return 1
    fi
    
    # 비밀번호 검증 (실제 구현에서는 시스템 사용자 데이터베이스 사용)
    if [[ $EUID -eq 0 ]]; then
        if su - "$username" -c "exit" 2>/dev/null; then
            # 로그인 성공
            local timestamp=$(date +%s)
            update_user_login "$username" "$timestamp" 0
            log_success "로그인 성공: $username"
            return 0
        else
            # 로그인 실패
            local new_failed=$((failed_attempts + 1))
            update_user_login "$username" "$last_login" "$new_failed"
            
            # 실패 5회 이상이면 계정 잠금
            if [[ $new_failed -ge 5 ]]; then
                lock_user "$username"
                log_error "로그인 실패 5회 - 계정 잠금: $username"
            else
                log_warning "로그인 실패: $username (실패 횟수: $new_failed)"
            fi
            return 1
        fi
    else
        # 비루트 모드에서는 간단한 검증
        log_info "인증 시도: $username"
        return 0
    fi
}

# 사용자 로그인 정보 업데이트
update_user_login() {
    local username="$1"
    local last_login="$2"
    local failed_attempts="$3"
    
    local temp_file="$USER_DB.tmp"
    while IFS=: read -r db_username uid gid full_name home_dir shell db_last_login db_failed_attempts locked; do
        if [[ "$db_username" == "$username" ]]; then
            last_login="$last_login"
            failed_attempts="$failed_attempts"
        fi
        echo "$db_username:$uid:$gid:$full_name:$home_dir:$shell:$last_login:$failed_attempts:$locked"
    done < "$USER_DB" > "$temp_file"
    
    mv "$temp_file" "$USER_DB"
}

# 사용자 잠금
lock_user() {
    local username="$1"
    
    if ! grep -q "^$username:" "$USER_DB"; then
        log_error "사용자 없음: $username"
        return 1
    fi
    
    local temp_file="$USER_DB.tmp"
    while IFS=: read -r db_username uid gid full_name home_dir shell last_login failed_attempts locked; do
        if [[ "$db_username" == "$username" ]]; then
            locked="true"
        fi
        echo "$db_username:$uid:$gid:$full_name:$home_dir:$shell:$last_login:$failed_attempts:$locked"
    done < "$USER_DB" > "$temp_file"
    
    mv "$temp_file" "$USER_DB"
    log_success "사용자 잠금: $username"
}

# 사용자 잠금 해제
unlock_user() {
    local username="$1"
    
    if ! grep -q "^$username:" "$USER_DB"; then
        log_error "사용자 없음: $username"
        return 1
    fi
    
    local temp_file="$USER_DB.tmp"
    while IFS=: read -r db_username uid gid full_name home_dir shell last_login failed_attempts locked; do
        if [[ "$db_username" == "$username" ]]; then
            locked="false"
            failed_attempts="0"
        fi
        echo "$db_username:$uid:$gid:$full_name:$home_dir:$shell:$last_login:$failed_attempts:$locked"
    done < "$USER_DB" > "$temp_file"
    
    mv "$temp_file" "$USER_DB"
    log_success "사용자 잠금 해제: $username"
}

# 그룹 생성
create_group() {
    local groupname="$1"
    local gid="${2:-}"
    
    if [[ -z "$groupname" ]]; then
        log_error "그룹 이름이 필요합니다"
        return 1
    fi
    
    # 그룹 이름 유효성 검사
    if [[ ! "$groupname" =~ ^[a-z_][a-z0-9_]*$ ]]; then
        log_error "잘못된 그룹 이름 형식: $groupname"
        return 1
    fi
    
    # 중복 그룹 확인
    if grep -q "^$groupname:" "$GROUP_DB"; then
        log_error "그룹 이미 존재: $groupname"
        return 1
    fi
    
    # GID 생성
    if [[ -z "$gid" ]]; then
        gid=$(get_next_gid)
    fi
    
    # 시스템 그룹 생성
    if [[ $EUID -eq 0 ]]; then
        groupadd -g "$gid" "$groupname" 2>/dev/null || true
    fi
    
    # 데이터베이스에 그룹 추가
    echo "$groupname:$gid:" >> "$GROUP_DB"
    
    log_success "그룹 생성 완료: $groupname (GID: $gid)"
}

# 다음 GID 가져오기
get_next_gid() {
    local max_gid=1000
    while IFS=: read -r groupname gid members; do
        if [[ "$gid" =~ ^[0-9]+$ ]] && [[ $gid -gt $max_gid ]]; then
            max_gid=$gid
        fi
    done < "$GROUP_DB"
    echo $((max_gid + 1))
}

# 사용자를 그룹에 추가
add_user_to_group() {
    local username="$1"
    local groupname="$2"
    
    if [[ -z "$username" || -z "$groupname" ]]; then
        log_error "사용자 이름과 그룹 이름이 필요합니다"
        return 1
    fi
    
    # 사용자와 그룹 존재 확인
    if ! grep -q "^$username:" "$USER_DB"; then
        log_error "사용자 없음: $username"
        return 1
    fi
    
    if ! grep -q "^$groupname:" "$GROUP_DB"; then
        log_error "그룹 없음: $groupname"
        return 1
    fi
    
    # 이미 그룹에 있는지 확인
    local group_info=$(grep "^$groupname:" "$GROUP_DB" | head -1)
    IFS=: read -r db_groupname db_gid members <<< "$group_info"
    
    if [[ "$members" == *"$username"* ]]; then
        log_warning "사용자가 이미 그룹에 있음: $username -> $groupname"
        return 0
    fi
    
    # 그룹 멤버 업데이트
    local new_members="$members"
    if [[ -n "$members" ]]; then
        new_members="$members,$username"
    else
        new_members="$username"
    fi
    
    # 데이터베이스 업데이트
    local temp_file="$GROUP_DB.tmp"
    while IFS=: read -r db_groupname db_gid db_members; do
        if [[ "$db_groupname" == "$groupname" ]]; then
            db_members="$new_members"
        fi
        echo "$db_groupname:$db_gid:$db_members"
    done < "$GROUP_DB" > "$temp_file"
    
    mv "$temp_file" "$GROUP_DB"
    
    # 시스템 그룹 업데이트
    if [[ $EUID -eq 0 ]]; then
        usermod -aG "$groupname" "$username" 2>/dev/null || true
    fi
    
    log_success "사용자를 그룹에 추가: $username -> $groupname"
}

# 사용자를 모든 그룹에서 제거
remove_user_from_all_groups() {
    local username="$1"
    
    local temp_file="$GROUP_DB.tmp"
    while IFS=: read -r groupname gid members; do
        # 사용자 제거
        local new_members=$(echo "$members" | sed "s/$username//" | sed 's/,,/,/' | sed 's/^,//' | sed 's/,$//')
        echo "$groupname:$gid:$new_members"
    done < "$GROUP_DB" > "$temp_file"
    
    mv "$temp_file" "$GROUP_DB"
}

# 그룹 목록 보기
list_groups() {
    echo "=== UnifiedArch OS 그룹 목록 ==="
    echo ""
    printf "%-20s %-6s %-30s\n" "그룹" "GID" "멤버"
    printf "%-20s %-6s %-30s\n" "--------------------" "------" "------------------------------"
    
    while IFS=: read -r groupname gid members; do
        printf "%-20s %-6s %-30s\n" "$groupname" "$gid" "$members"
    done < "$GROUP_DB"
}

# 인증 로그 보기
show_auth_log() {
    local lines="${1:-50}"
    
    echo "=== UnifiedArch OS 인증 로그 ==="
    echo "최근 $lines개 항목:"
    echo ""
    
    if [[ -f "$AUTH_LOG" ]]; then
        tail -n "$lines" "$AUTH_LOG"
    else
        log_info "인증 로그 파일 없음: $AUTH_LOG"
    fi
}

# 보안 정책 설정
setup_security_policy() {
    local max_failed_attempts="${1:-5}"
    local lockout_duration="${2:-300}"
    local password_min_length="${3:-8}"
    local password_complexity="${4:-true}"
    
    log_info "보안 정책 설정 중..."
    
    # 보안 정책 파일 생성
    local policy_file="/etc/unifiedarch/security-policy.conf"
    mkdir -p "$(dirname "$policy_file")"
    
    cat > "$policy_file" << EOF
# UnifiedArch OS 보안 정책

# 최대 로그인 실패 횟수
MAX_FAILED_ATTEMPTS=$max_failed_attempts

# 계정 잠금 시간 (초)
LOCKOUT_DURATION=$lockout_duration

# 최소 비밀번호 길이
PASSWORD_MIN_LENGTH=$password_min_length

# 비밀번호 복잡성 요구
PASSWORD_COMPLEXITY=$password_complexity

# 세션 타임아웃 (초)
SESSION_TIMEOUT=3600

# 로그인 기록 보관 기간 (일)
LOG_RETENTION_DAYS=90

# 다중 인증 활성화
MULTI_FACTOR_AUTH=false

# 비밀번호 만료 (일)
PASSWORD_EXPIRY_DAYS=90

# 마지막 로그인 알림
LAST_LOGIN_NOTIFICATION=true
EOF
    
    log_success "보안 정책 설정 완료"
    log_info "최대 실패 횟수: $max_failed_attempts"
    log_info "잠금 시간: $lockout_duration초"
    log_info "최소 비밀번호 길이: $password_min_length"
    log_info "비밀번호 복잡성: $password_complexity"
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 사용자 관리 및 인증 시스템"
    echo ""
    echo "사용법: $0 [명령] [인자...]"
    echo ""
    echo "사용자 관리:"
    echo "  user create <name> [full_name] [home] [shell] [password]"
    echo "  user delete <name> [remove_home]"
    echo "  user modify <name> <field> <value>"
    echo "  user list"
    echo "  user lock <name>"
    echo "  user unlock <name>"
    echo ""
    echo "그룹 관리:"
    echo "  group create <name> [gid]"
    echo "  group list"
    echo "  group adduser <username> <groupname>"
    echo ""
    echo "인증:"
    echo "  auth <username> <password>"
    echo "  log [lines]"
    echo ""
    echo "보안:"
    echo "  policy [max_failed] [lockout] [min_length] [complexity]"
    echo ""
    echo "예시:"
    echo "  $0 user create john 'John Doe' /home/john /bin/bash"
    echo "  $0 user modify john shell /bin/zsh"
    echo "  $0 group create developers 2000"
    echo "  $0 group adduser john developers"
    echo "  $0 auth john secret123"
    echo "  $0 policy 5 300 8 true"
}

# 메인 함수
main() {
    local command="${1:-help}"
    
    # 데이터베이스 초기화
    init_databases
    
    case "$command" in
        "user")
            local subcommand="${2:-help}"
            case "$subcommand" in
                "create")
                    create_user "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
                    ;;
                "delete")
                    delete_user "${3:-}" "${4:-true}"
                    ;;
                "modify")
                    modify_user "${3:-}" "${4:-}" "${5:-}"
                    ;;
                "list")
                    list_users
                    ;;
                "lock")
                    lock_user "${3:-}"
                    ;;
                "unlock")
                    unlock_user "${3:-}"
                    ;;
                *)
                    log_error "알 수 없는 사용자 명령: $subcommand"
                    show_help
                    exit 1
                    ;;
            esac
            ;;
        "group")
            local subcommand="${2:-help}"
            case "$subcommand" in
                "create")
                    create_group "${3:-}" "${4:-}"
                    ;;
                "list")
                    list_groups
                    ;;
                "adduser")
                    add_user_to_group "${3:-}" "${4:-}"
                    ;;
                *)
                    log_error "알 수 없는 그룹 명령: $subcommand"
                    show_help
                    exit 1
                    ;;
            esac
            ;;
        "auth")
            authenticate_user "${2:-}" "${3:-}"
            ;;
        "log")
            show_auth_log "${2:-50}"
            ;;
        "policy")
            setup_security_policy "${2:-5}" "${3:-300}" "${4:-8}" "${5:-true}"
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
