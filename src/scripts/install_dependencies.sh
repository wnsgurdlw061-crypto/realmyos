#!/bin/bash
# Massive OS 의존성 설치 스크립트
# Dependencies Installation Script

set -euo pipefail

# 스크립트 정보
SCRIPT_NAME="install_dependencies.sh"
SCRIPT_VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/massive_os_deps_install.log"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 로깅 함수
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} ${message}" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} ${message}" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${message}" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} ${message}" ;;
    esac
}

# 권한 체크
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "이 스크립트는 root 권한으로 실행해야 합니다."
        exit 1
    fi
}

# 패키지 매니저 감지
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        log "ERROR" "지원되는 패키지 매니저를 찾을 수 없습니다."
        exit 1
    fi
}

# 패키지 설치 함수
install_package() {
    local pkg_manager=$1
    local package=$2
    local description=$3
    
    log "INFO" "설치 중: ${package} (${description})"
    
    case $pkg_manager in
        "apt")
            if ! dpkg -l | grep -q "^ii  ${package} "; then
                apt install -y "${package}"
                log "INFO" "설치 완료: ${package}"
            else
                log "INFO" "이미 설치됨: ${package}"
            fi
            ;;
        "dnf"|"yum")
            if ! rpm -q "${package}" >/dev/null 2>&1; then
                "${pkg_manager}" install -y "${package}"
                log "INFO" "설치 완료: ${package}"
            else
                log "INFO" "이미 설치됨: ${package}"
            fi
            ;;
        "pacman")
            if ! pacman -Q "${package}" >/dev/null 2>&1; then
                pacman -S --noconfirm "${package}"
                log "INFO" "설치 완료: ${package}"
            else
                log "INFO" "이미 설치됨: ${package}"
            fi
            ;;
        "zypper")
            if ! zypper search -i "${package}" | grep -q "^i"; then
                zypper install -y "${package}"
                log "INFO" "설치 완료: ${package}"
            else
                log "INFO" "이미 설치됨: ${package}"
            fi
            ;;
    esac
}

# 개발 도구 설치
install_dev_tools() {
    local pkg_manager=$1
    
    log "INFO" "=== 개발 도구 설치 ==="
    
    # 기본 개발 도구
    local dev_packages=(
        "gcc:C 컴파일러"
        "g++:C++ 컴파일러"
        "make:빌드 도구"
        "cmake:빌드 시스템"
        "git:버전 관리"
        "vim:텍스트 편집기"
        "nano:텍스트 편집기"
        "curl:네트워크 도구"
        "wget:네트워크 도구"
        "tar:압축 도구"
        "gzip:압축 도구"
        "bzip2:압축 도구"
        "zip:압축 도구"
        "unzip:압축 도구"
    )
    
    # 패키지 매니저별 패키지 이름 변환
    case $pkg_manager in
        "apt")
            dev_packages+=(
                "build-essential:개발 필수 패키지"
                "pkg-config:패키지 설정"
                "autoconf:자동 설정"
                "automake:자동 빌드"
                "libtool:라이브러리 도구"
                "python3-dev:Python 개발"
                "python3-pip:Python 패키지 매니저"
                "libc6-dev:C 라이브러리 개발"
            )
            ;;
        "dnf"|"yum")
            dev_packages+=(
                "pkgconfig:패키지 설정"
                "autoconf:자동 설정"
                "automake:자동 빌드"
                "libtool:라이브러리 도구"
                "python3-devel:Python 개발"
                "python3-pip:Python 패키지 매니저"
                "glibc-devel:C 라이브러리 개발"
                "kernel-devel:커널 개발"
            )
            ;;
        "pacman")
            dev_packages+=(
                "pkgconf:패키지 설정"
                "autoconf:자동 설정"
                "automake:자동 빌드"
                "libtool:라이브러리 도구"
                "python:Python"
                "pip:Python 패키지 매니저"
                "base-devel:기본 개발 도구"
            )
            ;;
        "zypper")
            dev_packages+=(
                "pkg-config:패키지 설정"
                "autoconf:자동 설정"
                "automake:자동 빌드"
                "libtool:라이브러리 도구"
                "python3-devel:Python 개발"
                "python3-pip:Python 패키지 매니저"
                "glibc-devel:C 라이브러리 개발"
            )
            ;;
    esac
    
    for package_info in "${dev_packages[@]}"; do
        IFS=':' read -r package description <<< "$package_info"
        install_package "$pkg_manager" "$package" "$description"
    done
}

# 시스템 라이브러리 설치
install_system_libs() {
    local pkg_manager=$1
    
    log "INFO" "=== 시스템 라이브러리 설치 ==="
    
    # 기본 시스템 라이브러리
    local system_packages=(
        "libc6:C 표준 라이브러리"
        "libssl-dev:SSL 라이브러리 개발"
        "zlib1g-dev:압축 라이브러리 개발"
        "libncurses5-dev:ncurses 라이브러리 개발"
        "libreadline-dev:readline 라이브러리 개발"
        "libsqlite3-dev:SQLite 라이브러리 개발"
        "libxml2-dev:XML 라이브러리 개발"
        "libcurl4-openssl-dev:cURL 라이브러리 개발"
    )
    
    # 패키지 매니저별 패키지 이름 변환
    case $pkg_manager in
        "apt")
            system_packages+=(
                "libblkid-dev:블록 장치 라이브러리 개발"
                "libparted-dev:파티셔닝 라이브러리 개발"
                "libmount-dev:마운트 라이브러리 개발"
                "libjson-c-dev:JSON-C 라이브러리 개발"
                "libyaml-dev:YAML 라이브러리 개발"
                "libprocps-dev:프로세스 라이브러리 개발"
                "libsystemd-dev:systemd 라이브러리 개발"
            )
            ;;
        "dnf"|"yum")
            system_packages+=(
                "libblkid-devel:블록 장치 라이브러리 개발"
                "parted-devel:파티셔닝 라이브러리 개발"
                "libmount-devel:마운트 라이브러리 개발"
                "json-c-devel:JSON-C 라이브러리 개발"
                "libyaml-devel:YAML 라이브러리 개발"
                "procps-devel:프로세스 라이브러리 개발"
                "systemd-devel:systemd 라이브러리 개발"
            )
            ;;
        "pacman")
            system_packages+=(
                "libblkid:블록 장치 라이브러리"
                "parted:파티셔닝 라이브러리"
                "libmount:마운트 라이브러리"
                "json-c:JSON-C 라이브러리"
                "yaml:YAML 라이브러리"
                "procps:프로세스 라이브러리"
                "systemd:systemd 라이브러리"
            )
            ;;
        "zypper")
            system_packages+=(
                "libblkid-devel:블록 장치 라이브러리 개발"
                "parted-devel:파티셔닝 라이브러리 개발"
                "libmount-devel:마운트 라이브러리 개발"
                "json-c-devel:JSON-C 라이브러리 개발"
                "libyaml-devel:YAML 라이브러리 개발"
                "procps-devel:프로세스 라이브러리 개발"
                "systemd-devel:systemd 라이브러리 개발"
            )
            ;;
    esac
    
    for package_info in "${system_packages[@]}"; do
        IFS=':' read -r package description <<< "$package_info"
        install_package "$pkg_manager" "$package" "$description"
    done
}

# 커널 개발 도구 설치
install_kernel_dev() {
    local pkg_manager=$1
    
    log "INFO" "=== 커널 개발 도구 설치 ==="
    
    local kernel_packages=(
        "linux-headers-generic:커널 헤더"
        "linux-libc-dev:커널 C 라이브러리"
        "bc:계산기"
        "flex:어휘 분석기"
        "bison:파서 생성기"
        "libelf-dev:ELF 라이브러리 개발"
    )
    
    # 패키지 매니저별 패키지 이름 변환
    case $pkg_manager in
        "apt")
            kernel_packages+=(
                "linux-headers-$(uname -r):현재 커널 헤더"
                "libncurses-dev:ncurses 라이브러리 개발"
            )
            ;;
        "dnf"|"yum")
            kernel_packages=(
                "kernel-devel:커널 개발 파일"
                "kernel-headers:커널 헤더"
                "bc:계산기"
                "flex:어휘 분석기"
                "bison:파서 생성기"
                "elfutils-libelf-devel:ELF 라이브러리 개발"
                "ncurses-devel:ncurses 라이브러리 개발"
            )
            ;;
        "pacman")
            kernel_packages=(
                "linux-headers:커널 헤더"
                "bc:계산기"
                "flex:어휘 분석기"
                "bison:파서 생성기"
                "libelf:ELF 라이브러리"
                "ncurses:ncurses 라이브러리"
            )
            ;;
        "zypper")
            kernel_packages=(
                "kernel-devel:커널 개발 파일"
                "kernel-headers:커널 헤더"
                "bc:계산기"
                "flex:어휘 분석기"
                "bison:파서 생성기"
                "libelf-devel:ELF 라이브러리 개발"
                "ncurses-devel:ncurses 라이브러리 개발"
            )
            ;;
    esac
    
    for package_info in "${kernel_packages[@]}"; do
        IFS=':' read -r package description <<< "$package_info"
        install_package "$pkg_manager" "$package" "$description"
    done
}

# 파이썬 패키지 설치
install_python_packages() {
    log "INFO" "=== Python 패키지 설치 ==="
    
    # pip 업그레이드
    pip3 install --upgrade pip
    
    # 기본 Python 패키지
    local python_packages=(
        "setuptools:패키지 빌드 도구"
        "wheel:패키지 빌드 도구"
        "numpy:수치 계산 라이브러리"
        "scipy:과학 계산 라이브러리"
        "requests:HTTP 라이브러리"
        "pyyaml:YAML 파서"
        "jsonschema:JSON 스키마 검증"
        "psutil:시스템 정보 라이브러리"
        "cryptography:암호화 라이브러리"
        "click:커맨드 라인 인터페이스"
    )
    
    for package_info in "${python_packages[@]}"; do
        IFS=':' read -r package description <<< "$package_info"
        log "INFO" "설치 중: ${package} (${description})"
        pip3 install "${package}"
    done
}

# Ruby 패키지 설치
install_ruby_packages() {
    if command -v gem >/dev/null 2>&1; then
        log "INFO" "=== Ruby 패키지 설치 ==="
        
        local ruby_packages=(
            "bundler:번들러"
            "rake:빌드 도구"
        )
        
        for package_info in "${ruby_packages[@]}"; do
            IFS=':' read -r package description <<< "$package_info"
            log "INFO" "설치 중: ${package} (${description})"
            gem install "${package}"
        done
    fi
}

# Node.js 패키지 설치
install_node_packages() {
    if command -v npm >/dev/null 2>&1; then
        log "INFO" "=== Node.js 패키지 설치 ==="
        
        local node_packages=(
            "typescript:TypeScript 컴파일러"
            "eslint:자바스크립트 린터"
            "prettier:코드 포매터"
        )
        
        for package_info in "${node_packages[@]}"; do
            IFS=':' read -r package description <<< "$package_info"
            log "INFO" "설치 중: ${package} (${description})"
            npm install -g "${package}"
        done
    fi
}

# 시스템 서비스 설치
install_system_services() {
    local pkg_manager=$1
    
    log "INFO" "=== 시스템 서비스 설치 ==="
    
    local service_packages=(
        "openssh-server:SSH 서버"
        "cron:작업 스케줄러"
        "rsync:파일 동기화"
        "logrotate:로그 관리"
        "fail2ban:보안 도구"
    )
    
    # 패키지 매니저별 패키지 이름 변환
    case $pkg_manager in
        "apt")
            service_packages+=(
                "ssh:SSH 클라이언트/서버"
                "systemd:systemd"
            )
            ;;
        "dnf"|"yum")
            service_packages+=(
                "openssh:SSH 클라이언트/서버"
                "systemd:systemd"
            )
            ;;
        "pacman")
            service_packages+=(
                "openssh:SSH 클라이언트/서버"
                "systemd:systemd"
            )
            ;;
        "zypper")
            service_packages+=(
                "openssh:SSH 클라이언트/서버"
                "systemd:systemd"
            )
            ;;
    esac
    
    for package_info in "${service_packages[@]}"; do
        IFS=':' read -r package description <<< "$package_info"
        install_package "$pkg_manager" "$package" "$description"
    done
}

# 데이터베이스 설치
install_databases() {
    local pkg_manager=$1
    
    log "INFO" "=== 데이터베이스 설치 ==="
    
    local db_packages=(
        "sqlite3:SQLite 데이터베이스"
        "postgresql:PostgreSQL 데이터베이스"
        "mysql:MySQL 데이터베이스"
        "redis:Redis 키-값 저장소"
    )
    
    # 패키지 매니저별 패키지 이름 변환
    case $pkg_manager in
        "apt")
            db_packages=(
                "sqlite3:SQLite 데이터베이스"
                "postgresql:PostgreSQL 데이터베이스"
                "mysql-server:MySQL 데이터베이스 서버"
                "redis-server:Redis 서버"
            )
            ;;
        "dnf"|"yum")
            db_packages=(
                "sqlite:SQLite 데이터베이스"
                "postgresql-server:PostgreSQL 데이터베이스 서버"
                "mysql-server:MySQL 데이터베이스 서버"
                "redis:Redis 서버"
            )
            ;;
        "pacman")
            db_packages=(
                "sqlite:SQLite 데이터베이스"
                "postgresql:PostgreSQL 데이터베이스"
                "mysql:MySQL 데이터베이스"
                "redis:Redis"
            )
            ;;
        "zypper")
            db_packages=(
                "sqlite3:SQLite 데이터베이스"
                "postgresql-server:PostgreSQL 데이터베이스 서버"
                "mysql-community-server:MySQL 데이터베이스 서버"
                "redis:Redis"
            )
            ;;
    esac
    
    for package_info in "${db_packages[@]}"; do
        IFS=':' read -r package description <<< "$package_info"
        install_package "$pkg_manager" "$package" "$description"
    done
}

# 컨테이너 도구 설치
install_container_tools() {
    local pkg_manager=$1
    
    log "INFO" "=== 컨테이너 도구 설치 ==="
    
    local container_packages=(
        "docker:Docker 컨테이너"
        "docker-compose:Docker Compose"
        "podman:Podman 컨테이너"
        "buildah:컨테이너 빌드 도구"
    )
    
    for package_info in "${container_packages[@]}"; do
        IFS=':' read -r package description <<< "$package_info"
        install_package "$pkg_manager" "$package" "$description"
    done
}

# 개발 환경 설정
setup_dev_environment() {
    log "INFO" "=== 개발 환경 설정 ==="
    
    # 기본 디렉토리 생성
    mkdir -p /opt/massive-os/{src,lib,bin,include,share}
    mkdir -p /usr/local/src/massive-os
    mkdir -p /var/log/massive-os
    mkdir -p /var/lib/massive-os
    
    # 심볼릭 링크 생성
    if [[ ! -L /usr/local/massive-os ]]; then
        ln -sf /opt/massive-os /usr/local/massive-os
    fi
    
    # 환경 변수 설정
    cat >> /etc/environment << EOF
MASSIVE_OS_HOME=/opt/massive-os
MASSIVE_OS_PATH=/opt/massive-os/bin
PATH=\$PATH:/opt/massive-os/bin
EOF
    
    # 개발자 그룹 생성
    if ! getent group developers >/dev/null 2>&1; then
        groupadd developers
        log "INFO" "개발자 그룹 생성: developers"
    fi
    
    # 디렉토리 권한 설정
    chown -R root:developers /opt/massive-os
    chmod -R 775 /opt/massive-os
    
    log "INFO" "개발 환경 설정 완료"
}

# 설치 검증
verify_installation() {
    log "INFO" "=== 설치 검증 ==="
    
    # 컴파일러 검증
    if command -v gcc >/dev/null 2>&1; then
        local gcc_version=$(gcc --version | head -n1)
        log "INFO" "GCC: ${gcc_version}"
    fi
    
    # Python 검증
    if command -v python3 >/dev/null 2>&1; then
        local python_version=$(python3 --version)
        log "INFO" "Python: ${python_version}"
    fi
    
    # Git 검증
    if command -v git >/dev/null 2>&1; then
        local git_version=$(git --version)
        log "INFO" "Git: ${git_version}"
    fi
    
    # CMake 검증
    if command -v cmake >/dev/null 2>&1; then
        local cmake_version=$(cmake --version | head -n1)
        log "INFO" "CMake: ${cmake_version}"
    fi
    
    # 디렉토리 확인
    if [[ -d /opt/massive-os ]]; then
        log "INFO" "Massive OS 디렉토리: 존재함"
    else
        log "ERROR" "Massive OS 디렉토리: 존재하지 않음"
    fi
    
    log "INFO" "설치 검증 완료"
}

# 메인 함수
main() {
    log "INFO" "Massive OS 의존성 설치 시작"
    
    check_root
    
    # 패키지 매니저 감지
    local pkg_manager=$(detect_package_manager)
    log "INFO" "패키지 매니저: ${pkg_manager}"
    
    # 패키지 목록 업데이트
    log "INFO" "패키지 목록 업데이트 중..."
    case $pkg_manager in
        "apt")
            apt update
            ;;
        "dnf"|"yum")
            "${pkg_manager}" makecache
            ;;
        "pacman")
            pacman -Sy
            ;;
        "zypper")
            zypper refresh
            ;;
    esac
    
    # 의존성 설치 단계
    install_dev_tools "$pkg_manager"
    install_system_libs "$pkg_manager"
    install_kernel_dev "$pkg_manager"
    install_python_packages
    install_ruby_packages
    install_node_packages
    install_system_services "$pkg_manager"
    install_databases "$pkg_manager"
    install_container_tools "$pkg_manager"
    
    # 개발 환경 설정
    setup_dev_environment
    
    # 설치 검증
    verify_installation
    
    log "INFO" "Massive OS 의존성 설치 완료"
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
