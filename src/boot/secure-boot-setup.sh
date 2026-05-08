#!/bin/bash
#
# UnifiedArch OS Secure Boot Setup
# Secure Boot 키 생성 및 등록 스크립트
#
# 기능:
# - MOK (Machine Owner Key) 생성
# - DB 키 등록
# - shim/grub 서명
# - 자동 키 관리
#

set -euo pipefail

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOK_DIR="/var/lib/unifiedarch/mok"
DB_DIR="/var/lib/unifiedarch/db"
CERT_DIR="/etc/unifiedarch/certs"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${PURPLE}[STEP]${NC} $1"; }

# UEFI 확인
check_uefi() {
    if [[ ! -d "/sys/firmware/efi" ]]; then
        log_error "UEFI 시스템이 아닙니다"
        return 1
    fi
}

# 필수 도구 확인
check_tools() {
    local tools=("openssl" "mokutil" "efibootmgr" "sbsign")
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "필수 도구가 없습니다: $tool"
            return 1
        fi
    done
}

# 디렉토리 생성
create_directories() {
    mkdir -p "$MOK_DIR" "$DB_DIR" "$CERT_DIR"
    chmod 700 "$MOK_DIR" "$DB_DIR"
    chmod 755 "$CERT_DIR"
}

# MOK 키 생성
create_mok_keys() {
    log_step "MOK 키 생성 중..."
    
    local mok_priv="$MOK_DIR/MOK.priv"
    local mok_der="$MOK_DIR/MOK.der"
    
    if [[ -f "$mok_priv" && -f "$mok_der" ]]; then
        log_info "기존 MOK 키 발견"
        return 0
    fi
    
    # 개인 키 생성
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
        -out "$mok_priv" 2>/dev/null || {
        log_error "MOK 개인 키 생성 실패"
        return 1
    }
    
    # 공개 키 생성
    openssl req -new -x509 -key "$mok_priv" -out "$mok_der" \
        -days 36500 -subj "/CN=UnifiedArch OS MOK/" 2>/dev/null || {
        log_error "MOK 공개 키 생성 실패"
        return 1
    }
    
    chmod 600 "$mok_priv"
    chmod 644 "$mok_der"
    
    log_success "MOK 키 생성 완료"
}

# DB 키 생성
create_db_keys() {
    log_step "DB (Database) 키 생성 중..."
    
    local db_priv="$DB_DIR/DB.priv"
    local db_der="$DB_DIR/DB.der"
    
    if [[ -f "$db_priv" && -f "$db_der" ]]; then
        log_info "기존 DB 키 발견"
        return 0
    fi
    
    # 개인 키 생성
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
        -out "$db_priv" 2>/dev/null || {
        log_error "DB 개인 키 생성 실패"
        return 1
    }
    
    # 공개 키 생성
    openssl req -new -x509 -key "$db_priv" -out "$db_der" \
        -days 36500 -subj "/CN=UnifiedArch OS DB/" 2>/dev/null || {
        log_error "DB 공개 키 생성 실패"
        return 1
    }
    
    chmod 600 "$db_priv"
    chmod 644 "$db_der"
    
    log_success "DB 키 생성 완료"
}

# KEK (Key Exchange Key) 생성
create_kek_keys() {
    log_step "KEK 키 생성 중..."
    
    local kek_priv="$DB_DIR/KEK.priv"
    local kek_der="$DB_DIR/KEK.der"
    
    if [[ -f "$kek_priv" && -f "$kek_der" ]]; then
        log_info "기존 KEK 키 발견"
        return 0
    fi
    
    # 개인 키 생성
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
        -out "$kek_priv" 2>/dev/null || {
        log_error "KEK 개인 키 생성 실패"
        return 1
    }
    
    # 공개 키 생성
    openssl req -new -x509 -key "$kek_priv" -out "$kek_der" \
        -days 36500 -subj "/CN=UnifiedArch OS KEK/" 2>/dev/null || {
        log_error "KEK 공개 키 생성 실패"
        return 1
    }
    
    chmod 600 "$kek_priv"
    chmod 644 "$kek_der"
    
    log_success "KEK 키 생성 완료"
}

# PK (Platform Key) 생성
create_pk_keys() {
    log_step "PK 키 생성 중..."
    
    local pk_priv="$DB_DIR/PK.priv"
    local pk_der="$DB_DIR/PK.der"
    
    if [[ -f "$pk_priv" && -f "$pk_der" ]]; then
        log_info "기존 PK 키 발견"
        return 0
    fi
    
    # 개인 키 생성
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
        -out "$pk_priv" 2>/dev/null || {
        log_error "PK 개인 키 생성 실패"
        return 1
    }
    
    # 공개 키 생성
    openssl req -new -x509 -key "$pk_priv" -out "$pk_der" \
        -days 36500 -subj "/CN=UnifiedArch OS PK/" 2>/dev/null || {
        log_error "PK 공개 키 생성 실패"
        return 1
    }
    
    chmod 600 "$pk_priv"
    chmod 644 "$pk_der"
    
    log_success "PK 키 생성 완료"
}

# MOK 등록
enroll_mok() {
    log_step "MOK 등록 중..."
    
    if ! mokutil --import "$MOK_DIR/MOK.der" 2>/dev/null; then
        log_warning "MOK 등록 실패 - 재부팅 후 수동 등록 필요"
        log_info "재부팅 후 MOK 관리자에서 키를 등록하세요"
    else
        log_success "MOK 등록 완료"
    fi
}

# shim/grub 서명
sign_bootloaders() {
    log_step "부트로더 서명 중..."
    
    local shim_path="/usr/lib/shim/shimx64.efi"
    local grub_path="/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed"
    local mok_der="$MOK_DIR/MOK.der"
    local mok_priv="$MOK_DIR/MOK.priv"
    
    # 서명된 부트로더 확인
    if [[ -f "$shim_path.signed" && -f "$grub_path" ]]; then
        log_info "서명된 부트로더 발견"
        return 0
    fi
    
    # shim 서명
    if [[ -f "$shim_path" ]]; then
        sbsign --key "$mok_priv" --cert "$mok_der" \
            --output "$shim_path.signed" "$shim_path" 2>/dev/null || {
            log_error "shim 서명 실패"
            return 1
        }
        log_success "shim 서명 완료"
    fi
    
    # GRUB 서명
    if [[ -f "/usr/lib/grub/x86_64-efi/grubx64.efi" ]]; then
        sbsign --key "$mok_priv" --cert "$mok_der" \
            --output "$grub_path" "/usr/lib/grub/x86_64-efi/grubx64.efi" 2>/dev/null || {
            log_error "GRUB 서명 실패"
            return 1
        }
        log_success "GRUB 서명 완료"
    fi
}

# 커널 서명
sign_kernel() {
    log_step "커널 서명 중..."
    
    local mok_der="$MOK_DIR/MOK.der"
    local mok_priv="$MOK_DIR/MOK.priv"
    
    # 현재 커널 서명
    local kernel_version=$(uname -r)
    local kernel_path="/boot/vmlinuz-$kernel_version"
    
    if [[ -f "$kernel_path" ]]; then
        sbsign --key "$mok_priv" --cert "$mok_der" \
            --output "$kernel_path.signed" "$kernel_path" 2>/dev/null || {
            log_error "커널 서명 실패"
            return 1
        }
        
        # 원본 백업 및 서명된 버전으로 교체
        cp "$kernel_path" "$kernel_path.backup"
        mv "$kernel_path.signed" "$kernel_path"
        
        log_success "커널 서명 완료"
    else
        log_warning "커널 파일을 찾을 수 없음"
    fi
}

# Secure Boot 상태 확인
check_secure_boot_status() {
    log_step "Secure Boot 상태 확인 중..."
    
    echo ""
    echo "========================================="
    echo "  Secure Boot 상태"
    echo "========================================="
    echo ""
    
    # 기본 상태
    if command -v mokutil &>/dev/null; then
        echo "Secure Boot: $(mokutil --sb-state 2>/dev/null || echo "알 수 없음")"
        echo "MOK 상태: $(mokutil --list-enrolled 2>/dev/null | wc -l)개 키 등록됨"
    else
        echo "mokutil을 찾을 수 없음"
    fi
    
    # UEFI 변수
    if [[ -d "/sys/firmware/efi/efivars" ]]; then
        echo "UEFI 변수: 접근 가능"
    else
        echo "UEFI 변수: 접근 불가"
    fi
    
    # 키 파일 상태
    echo ""
    echo "키 파일 상태:"
    [[ -f "$MOK_DIR/MOK.priv" ]] && echo "  MOK 개인 키: 있음" || echo "  MOK 개인 키: 없음"
    [[ -f "$MOK_DIR/MOK.der" ]] && echo "  MOK 공개 키: 있음" || echo "  MOK 공개 키: 없음"
    [[ -f "$DB_DIR/DB.priv" ]] && echo "  DB 개인 키: 있음" || echo "  DB 개인 키: 없음"
    [[ -f "$DB_DIR/DB.der" ]] && echo "  DB 공개 키: 있음" || echo "  DB 공개 키: 없음"
    
    # 서명된 파일 상태
    echo ""
    echo "서명된 파일:"
    [[ -f "/usr/lib/shim/shimx64.efi.signed" ]] && echo "  shim: 서명됨" || echo "  shim: 미서명"
    [[ -f "/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" ]] && echo "  GRUB: 서명됨" || echo "  GRUB: 미서명"
    
    echo "========================================="
}

# 자동 서명 설정
setup_auto_signing() {
    log_step "자동 서명 설정 중..."
    
    # dkms 자동 서명 설정
    cat > /etc/dkms/framework.conf.d/unifiedarch.conf << 'EOF'
# UnifiedArch OS DKMS 자동 서명 설정

SIGN_MODULE="yes"
MOK_SIGNING_KEY="/var/lib/unifiedarch/mok/MOK.priv"
MOK_CERTIFICATE="/var/lib/unifiedarch/mok/MOK.der"
EOF
    
    # pacman hook 설정 (Arch 계열)
    if command -v pacman &>/dev/null; then
        mkdir -p /etc/pacman.d/hooks
        
        cat > /etc/pacman.d/hooks/95-secure-sign.hook << 'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = File
Target = boot/vmlinuz-*

[Action]
Description = Signing kernel with MOK...
When = PostTransaction
Exec = /usr/local/bin/unifiedarch-sign-kernel %f
EOF
        
        # 커널 서명 스크립트
        cat > /usr/local/bin/unifiedarch-sign-kernel << 'EOF'
#!/bin/bash
# UnifiedArch OS 커널 자동 서명 스크립트

MOK_PRIV="/var/lib/unifiedarch/mok/MOK.priv"
MOK_DER="/var/lib/unifiedarch/mok/MOK.der"

if [[ -f "$MOK_PRIV" && -f "$MOK_DER" && -f "$1" ]]; then
    sbsign --key "$MOK_PRIV" --cert "$MOK_DER" --output "$1.signed" "$1"
    mv "$1.signed" "$1"
fi
EOF
        
        chmod +x /usr/local/bin/unifiedarch-sign-kernel
        
        log_success "자동 서명 설정 완료"
    else
        log_warning "pacman을 찾을 수 없음 - 자동 서명 설정 건너뜀"
    fi
}

# 키 백업
backup_keys() {
    log_step "키 백업 중..."
    
    local backup_dir="/var/lib/unifiedarch/backup/$(date +%Y%m%d)"
    mkdir -p "$backup_dir"
    
    # 모든 키 백업
    cp -r "$MOK_DIR" "$backup_dir/" 2>/dev/null || true
    cp -r "$DB_DIR" "$backup_dir/" 2>/dev/null || true
    cp -r "$CERT_DIR" "$backup_dir/" 2>/dev/null || true
    
    # 백업 암호화
    if command -v gpg &>/dev/null; then
        tar -czf - "$backup_dir" | gpg --cipher-algo AES256 --symmetric --output "$backup_dir.tar.gz.gpg"
        rm -rf "$backup_dir"
        log_success "키 백업 완료 (암호화됨): $backup_dir.tar.gz.gpg"
    else
        tar -czf "$backup_dir.tar.gz" "$backup_dir"
        rm -rf "$backup_dir"
        log_success "키 백업 완료: $backup_dir.tar.gz"
    fi
}

# 도움말
show_help() {
    echo "UnifiedArch OS Secure Boot Setup"
    echo ""
    echo "사용법: $0 [명령어]"
    echo ""
    echo "명령어:"
    echo "  setup           - 전체 Secure Boot 설정"
    echo "  create-keys     - 키 생성만 수행"
    echo "  enroll-mok      - MOK 등록"
    echo "  sign-boot       - 부트로더 서명"
    echo "  sign-kernel     - 커널 서명"
    echo "  auto-sign       - 자동 서명 설정"
    echo "  status          - 상태 확인"
    echo "  backup          - 키 백업"
    echo "  help            - 이 도움말"
    echo ""
    echo "참고: 설정 후 재부팅하고 MOK 등록을 완료해야 합니다"
}

# 메인 함수
main() {
    local action="${1:-help}"
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "루트 권한이 필요합니다"
        exit 1
    fi
    
    # UEFI 확인
    check_uefi
    
    # 도구 확인
    check_tools
    
    # 디렉토리 생성
    create_directories
    
    case "$action" in
        setup)
            log_info "Secure Boot 전체 설정 시작"
            create_mok_keys
            create_db_keys
            create_kek_keys
            create_pk_keys
            enroll_mok
            sign_bootloaders
            sign_kernel
            setup_auto_signing
            check_secure_boot_status
            log_success "Secure Boot 설정 완료 - 재부팅 후 MOK 등록 필요"
            ;;
        create-keys)
            create_mok_keys
            create_db_keys
            create_kek_keys
            create_pk_keys
            log_success "키 생성 완료"
            ;;
        enroll-mok)
            enroll_mok
            ;;
        sign-boot)
            sign_bootloaders
            ;;
        sign-kernel)
            sign_kernel
            ;;
        auto-sign)
            setup_auto_signing
            ;;
        status)
            check_secure_boot_status
            ;;
        backup)
            backup_keys
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
