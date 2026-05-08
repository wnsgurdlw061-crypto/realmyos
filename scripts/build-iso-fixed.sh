#!/bin/bash
#
# UnifiedArch OS ISO Build Script
# archiso를 사용한 부팅 가능한 ISO 이미지 생성
#
# 사용법: sudo ./build-iso-fixed.sh [옵션]
#

set -euo pipefail

# ========== 설정 ==========
VERSION="${VERSION:-1.0.0}"
BUILD_DATE=$(date +%Y%m%d)
ISO_NAME="unifiedarch-${VERSION}-${BUILD_DATE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build"
PROFILE_DIR="${BUILD_DIR}/iso/profile"
WORK_DIR="${BUILD_DIR}/iso/work"
OUT_DIR="${BUILD_DIR}/iso/out"
FINAL_DIR="${BUILD_DIR}/final"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ========== 로그 함수 ==========
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${PURPLE}[STEP]${NC} $1"; }

banner() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
  _   _   _   _   _   _   _   _   _  
 / \ / \ / \ / \ / \ / \ / \ / \ / \ 
( U | n | i | f | i | e | d | A | r )
 \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ 
                                     
   UnifiedArch OS ISO Builder v1.0
         Bootable Live System
EOF
    echo -e "${NC}"
}

# ========== 환경 확인 ==========
check_environment() {
    log_step "빌드 환경 확인 중..."

    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 루트 권한으로 실행해야 합니다."
        log_info "사용법: sudo $0"
        exit 1
    fi

    # archiso 확인
    if ! command -v mkarchiso &>/dev/null; then
        log_error "archiso가 설치되지 않았습니다."
        log_info "설치: sudo pacman -S archiso"
        exit 1
    fi

    # 필수 도구 확인
    local required_tools=("pacman" "git" "tar" "gzip" "squashfs-tools" "xorriso" "mtools")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "필수 도구가 없습니다: $tool"
            exit 1
        fi
    done

    # 디스크 공간 확인 (최소 20GB)
    local available_space=$(df -BG "$PROJECT_ROOT" | tail -n1 | awk '{print $4}' | sed 's/G//')
    if [[ $available_space -lt 20 ]]; then
        log_warning "디스크 공간이 부족할 수 있습니다. (현재: ${available_space}GB, 권장: 20GB 이상)"
    fi

    log_success "빌드 환경 확인 완료"
}

# ========== 디렉토리 준비 ==========
prepare_directories() {
    log_step "디렉토리 준비 중..."

    mkdir -p "$WORK_DIR"
    mkdir -p "$OUT_DIR"
    mkdir -p "$FINAL_DIR"

    # 프로필 디렉토리 확인
    if [[ ! -d "$PROFILE_DIR" ]]; then
        log_error "archiso 프로필 디렉토리가 없습니다: $PROFILE_DIR"
        log_info "먼저 프로필을 생성하세요."
        exit 1
    fi

    # 필수 파일 확인
    local required_files=(
        "$PROFILE_DIR/profiledef.sh"
        "$PROFILE_DIR/packages.x86_64"
        "$PROFILE_DIR/pacman.conf"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "필수 파일이 없습니다: $file"
            exit 1
        fi
    done

    log_success "디렉토리 준비 완료"
}

# ========== 커널 모듈 빌드 ==========
build_kernel_modules() {
    log_step "커널 모듈 빌드 중..."

    local kernel_src="$PROJECT_ROOT/src/kernel"
    local module_dest="$PROFILE_DIR/airootfs/usr/lib/unifiedarch/modules"

    mkdir -p "$module_dest"

    if [[ -d "$kernel_src" ]]; then
        cd "$kernel_src"

        # 커널 모듈 빌드
        if make clean && make -j$(nproc); then
            # .ko 파일 복사
            find . -name "*.ko" -exec cp {} "$module_dest/" \;

            local module_count=$(find "$module_dest" -name "*.ko" | wc -l)
            if [[ $module_count -gt 0 ]]; then
                log_success "커널 모듈 빌드 완료: $module_count개 모듈"
            else
                log_warning "빌드된 커널 모듈이 없습니다."
            fi
        else
            log_warning "커널 모듈 빌드 실패. 기본 커널만 사용합니다."
        fi

        cd "$PROJECT_ROOT"
    else
        log_warning "커널 소스 디렉토리가 없습니다. 기본 커널만 사용합니다."
    fi
}

# ========== Calamares 브랜딩 ==========
setup_calamares_branding() {
    log_step "Calamares 브랜딩 설정 중..."

    local branding_dir="$PROFILE_DIR/airootfs/usr/share/calamares/branding/unifiedarch"

    mkdir -p "$branding_dir"

    # 브랜딩 설정 파일
    cat > "$branding_dir/branding.desc" << 'EOF'
componentName: unifiedarch

welcomeStyle:
  sidebar: true
  welcomeStyle: true

string:
  productName: UnifiedArch OS
  shortProductName: UnifiedArch
  version: 1.0.0
  shortVersion: 1.0
  versionedName: UnifiedArch OS 1.0.0 "Aurora"
  shortVersionedName: UnifiedArch 1.0
  bootloaderEntryName: UnifiedArch
  productUrl: https://unifiedarch.org
  supportUrl: https://community.unifiedarch.org
  knownIssuesUrl: https://bugs.unifiedarch.org
  releaseNotesUrl: https://unifiedarch.org/releases/1.0.0

images:
  productLogo: "logo.png"
  productIcon: "logo.png"
  productWelcome: "welcome.png"

slideshow: "show.qml"
slideshowAPI: 1

style:
  sidebarBackground: "#2c3e50"
  sidebarText: "#ecf0f1"
  sidebarTextHighlight: "#3498db"
  sidebarTextSelect: "#ffffff"
EOF

    # QML 슬라이드쇼
    cat > "$branding_dir/show.qml" << 'EOF'
import QtQuick 2.7
import calamares.slideshow 1.0

Presentation {
    id: presentation
    loopSlides: true

    Slide {
        title: qsTr("Welcome to UnifiedArch OS")
        centeredText: qsTr("A unified Linux distribution combining the best of all worlds.")
    }

    Slide {
        title: qsTr("Arch Linux Based")
        centeredText: qsTr("Rolling release with access to the Arch User Repository.")
    }

    Slide {
        title: qsTr("User Friendly")
        centeredText: qsTr("Easy installation with Calamares and GNOME desktop.")
    }

    Slide {
        title: qsTr("Secure & Fast")
        centeredText: qsTr("Built-in security features and optimized performance.")
    }
}
EOF

    log_success "Calamares 브랜딩 설정 완료"
}

# ========== 미러리스트 설정 ==========
setup_mirrorlist() {
    log_step "미러리스트 설정 중..."

    mkdir -p "$PROFILE_DIR/airootfs/etc/pacman.d"

    # 한국 미러 우선
    cat > "$PROFILE_DIR/airootfs/etc/pacman.d/mirrorlist" << 'EOF'
# Korea
Server = https://mirror.funami.tech/archlinux/$repo/os/$arch
Server = https://mirror.premi.st/archlinux/$repo/os/$arch
Server = https://ftp.harukasan.org/archlinux/$repo/os/$arch

# Japan
Server = https://ftp.tsukuba.wide.ad.jp/Linux/archlinux/$repo/os/$arch
Server = https://ftp.jaist.ac.jp/pub/Linux/ArchLinux/$repo/os/$arch

# Global
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF

    log_success "미러리스트 설정 완료"
}

# ========== ISO 빌드 ==========
build_iso() {
    log_step "ISO 빌드 시작..."
    log_info "이 과정은 30분~1시간 정도 소요될 수 있습니다."

    cd "$PROFILE_DIR"

    # mkarchiso 실행
    if mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" .; then
        log_success "ISO 빌드 완료"
        return 0
    else
        log_error "ISO 빌드 실패"
        return 1
    fi
}

# ========== 결과 처리 ==========
finalize_build() {
    log_step "결과 처리 중..."

    # 생성된 ISO 파일 찾기
    local iso_file=$(find "$OUT_DIR" -name "*.iso" | head -n1)

    if [[ -n "$iso_file" && -f "$iso_file" ]]; then
        # 최종 파일명으로 복사
        local final_iso="$FINAL_DIR/${ISO_NAME}.iso"
        cp "$iso_file" "$final_iso"

        # 체크섬 생성
        cd "$FINAL_DIR"
        sha256sum "${ISO_NAME}.iso" > "${ISO_NAME}.iso.sha256"
        md5sum "${ISO_NAME}.iso" > "${ISO_NAME}.iso.md5"

        # 파일 정보
        local iso_size=$(du -h "$final_iso" | cut -f1)

        log_success "ISO 생성 완료!"
        echo ""
        echo -e "${GREEN}${BOLD}========================================${NC}"
        echo -e "${GREEN}${BOLD}  UnifiedArch OS ISO Build Complete!${NC}"
        echo -e "${GREEN}${BOLD}========================================${NC}"
        echo ""
        echo -e "  ${BOLD}ISO 파일:${NC} $final_iso"
        echo -e "  ${BOLD}크기:${NC} $iso_size"
        echo -e "  ${BOLD}SHA256:${NC} ${ISO_NAME}.iso.sha256"
        echo -e "  ${BOLD}MD5:${NC} ${ISO_NAME}.iso.md5"
        echo ""
        echo -e "  ${BOLD}테스트 명령어:${NC}"
        echo -e "  qemu-system-x86_64 -m 4G -smp 2 -enable-kvm \\"
        echo -e "    -cdrom $final_iso -boot d"
        echo ""
        echo -e "  ${BOLD}USB 굽기:${NC}"
        echo -e "  sudo dd if=$final_iso of=/dev/sdX bs=4M status=progress && sync"
        echo ""

    else
        log_error "ISO 파일을 찾을 수 없습니다."
        return 1
    fi
}

# ========== 정리 ==========
cleanup() {
    log_step "임시 파일 정리 중..."

    if [[ "${CLEUP:-false}" == "true" ]]; then
        rm -rf "$WORK_DIR"
        log_info "작업 디렉토리 정리 완료"
    fi
}

# ========== 도움말 ==========
show_help() {
    echo "UnifiedArch OS ISO 빌드 스크립트"
    echo ""
    echo "사용법: sudo $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  build       - ISO 빌드 (기본)"
    echo "  clean       - 빌드 파일 정리"
    echo "  help        - 이 도움말"
    echo ""
    echo "환경 변수:"
    echo "  VERSION     - 버전 번호 (기본: 1.0.0)"
    echo "  CLEANUP     - 빌드 후 정리 (true/false)"
    echo ""
    echo "요구사항:"
    echo "  - Arch Linux 기반 시스템"
    echo "  - archiso 패키지"
    echo "  - 루트 권한"
    echo "  - 최소 20GB 디스크 공간"
}

# ========== 메인 ==========
main() {
    local action="${1:-build}"

    case "$action" in
        build)
            banner
            check_environment
            prepare_directories
            build_kernel_modules
            setup_calamares_branding
            setup_mirrorlist
            if build_iso; then
                finalize_build
                cleanup
            fi
            ;;
        clean)
            log_info "빌드 파일 정리 중..."
            rm -rf "$WORK_DIR" "$OUT_DIR" "$FINAL_DIR"
            log_success "정리 완료"
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            log_error "알 수 없는 옵션: $action"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
