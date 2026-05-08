#!/bin/bash
# Massive OS 빌드 시스템
# Build System Script

set -euo pipefail

# 스크립트 정보
SCRIPT_NAME="build_system.sh"
SCRIPT_VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
BUILD_DIR="${PROJECT_ROOT}/build"
LOG_FILE="/var/log/massive_os_build.log"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 빌드 설정
BUILD_TYPE="release"
BUILD_TARGET="all"
PARALLEL_JOBS=$(nproc)
ENABLE_TESTS="true"
ENABLE_INSTALL="true"
CLEAN_BUILD="false"
VERBOSE_BUILD="false"

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

# 도움말 표시
show_help() {
    cat << EOF
Massive OS 빌드 시스템 v${SCRIPT_VERSION}

사용법: $0 [옵션] [타겟]

옵션:
  -t, --type TYPE        빌드 타입 (debug|release|profile) [기본값: release]
  -j, --jobs NUM         병렬 작업 수 [기본값: $(nproc)]
  -c, --clean            빌드 디렉토리 정리
  -v, --verbose          상세 빌드 출력
  --no-tests             테스트 비활성화
  --no-install           설치 비활성화
  --prefix PATH          설치 접두사 [기본값: /usr/local]
  --sysroot PATH         시스템 루트 디렉토리
  --cross-compile        교차 컴파일 활성화
  --target ARCH          대상 아키텍처
  -h, --help             이 도움말 표시

타겟:
  all                    모든 컴포넌트 빌드 (기본값)
  kernel                 커널 모듈 빌드
  packages               패키지 관리자 빌드
  installer              설치 프로그램 빌드
  tools                  시스템 도구 빌드
  tests                  테스트 빌드 및 실행
  clean                  빌드 정리
  install                설치
  package                패키징

예제:
  $0 --type release --jobs 8 all
  $0 --clean --type debug kernel
  $0 --no-tests --prefix /opt/massive-os install

EOF
}

# 인자 파싱
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                BUILD_TYPE="$2"
                shift 2
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -c|--clean)
                CLEAN_BUILD="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE_BUILD="true"
                shift
                ;;
            --no-tests)
                ENABLE_TESTS="false"
                shift
                ;;
            --no-install)
                ENABLE_INSTALL="false"
                shift
                ;;
            --prefix)
                INSTALL_PREFIX="$2"
                shift 2
                ;;
            --sysroot)
                SYSROOT="$2"
                shift 2
                ;;
            --cross-compile)
                CROSS_COMPILE="true"
                shift
                ;;
            --target)
                TARGET_ARCH="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            all|kernel|packages|installer|tools|tests|clean|install|package)
                BUILD_TARGET="$1"
                shift
                ;;
            *)
                log "ERROR" "알 수 없는 인자: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 환경 설정
setup_environment() {
    log "INFO" "=== 빌드 환경 설정 ==="
    
    # 기본값 설정
    INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
    SYSROOT="${SYSROOT:-/}"
    TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
    
    # 빌드 디렉토리 설정
    BUILD_DIR="${PROJECT_ROOT}/build/${BUILD_TYPE}"
    mkdir -p "${BUILD_DIR}"
    
    # 환경 변수 설정
    export CC="${CC:-gcc}"
    export CXX="${CXX:-g++}"
    export CFLAGS="${CFLAGS:--O2 -Wall -Wextra}"
    export CXXFLAGS="${CXXFLAGS:--O2 -Wall -Wextra}"
    export LDFLAGS="${LDFLAGS:-}"
    export MAKEFLAGS="${MAKEFLAGS:--j${PARALLEL_JOBS}}"
    
    # 빌드 타입별 설정
    case $BUILD_TYPE in
        "debug")
            export CFLAGS="${CFLAGS} -g -O0 -DDEBUG"
            export CXXFLAGS="${CXXFLAGS} -g -O0 -DDEBUG"
            ;;
        "release")
            export CFLAGS="${CFLAGS} -O3 -DNDEBUG"
            export CXXFLAGS="${CXXFLAGS} -O3 -DNDEBUG"
            ;;
        "profile")
            export CFLAGS="${CFLAGS} -O2 -g -pg"
            export CXXFLAGS="${CXXFLAGS} -O2 -g -pg"
            ;;
    esac
    
    # 교차 컴파일 설정
    if [[ "${CROSS_COMPILE}" == "true" ]]; then
        case $TARGET_ARCH in
            "x86_64")
                export CC="x86_64-linux-gnu-gcc"
                export CXX="x86_64-linux-gnu-g++"
                ;;
            "aarch64")
                export CC="aarch64-linux-gnu-gcc"
                export CXX="aarch64-linux-gnu-g++"
                ;;
            "arm")
                export CC="arm-linux-gnueabihf-gcc"
                export CXX="arm-linux-gnueabihf-g++"
                ;;
        esac
        log "INFO" "교차 컴파일 활성화: ${TARGET_ARCH}"
    fi
    
    # 빌드 정보 표시
    log "INFO" "빌드 타입: ${BUILD_TYPE}"
    log "INFO" "빌드 타겟: ${BUILD_TARGET}"
    log "INFO" "병렬 작업: ${PARALLEL_JOBS}"
    log "INFO" "설치 접두사: ${INSTALL_PREFIX}"
    log "INFO" "시스템 루트: ${SYSROOT}"
    log "INFO" "대상 아키텍처: ${TARGET_ARCH}"
    log "INFO" "컴파일러: ${CC}"
    
    log "INFO" "빌드 환경 설정 완료"
}

# 빌드 정리
clean_build() {
    log "INFO" "빌드 디렉토리 정리 중..."
    
    if [[ -d "${BUILD_DIR}" ]]; then
        rm -rf "${BUILD_DIR}"
        log "INFO" "빌드 디렉토리 삭제: ${BUILD_DIR}"
    fi
    
    # 프로젝트 루트의 빌드 파일 정리
    find "${PROJECT_ROOT}" -name "*.o" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}" -name "*.so" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}" -name "*.a" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}" -name "CMakeCache.txt" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}" -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null || true
    find "${PROJECT_ROOT}" -name "Makefile" -delete 2>/dev/null || true
    
    log "INFO" "빌드 정리 완료"
}

# 의존성 체크
check_dependencies() {
    log "INFO" "의존성 확인 중..."
    
    local missing_deps=()
    
    # 필수 도구 확인
    local required_tools=("gcc" "g++" "make" "cmake" "pkg-config")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    # 필수 라이브러리 확인
    local required_libs=("ssl" "crypto" "z" "ncurses" "sqlite3")
    for lib in "${required_libs[@]}"; do
        if ! ldconfig -p | grep -q "lib${lib}"; then
            missing_deps+=("lib${lib}-dev")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "누락된 의존성:"
        for dep in "${missing_deps[@]}"; do
            log "ERROR" "  - ${dep}"
        done
        log "ERROR" "의존성 설치 스크립트를 실행하세요: ./install_dependencies.sh"
        exit 1
    fi
    
    log "INFO" "의존성 확인 완료"
}

# CMake 빌드 설정
setup_cmake_build() {
    local component=$1
    local component_dir="${PROJECT_ROOT}/src/${component}"
    local build_subdir="${BUILD_DIR}/${component}"
    
    if [[ ! -d "${component_dir}" ]]; then
        log "ERROR" "컴포넌트 디렉토리를 찾을 수 없습니다: ${component_dir}"
        return 1
    fi
    
    mkdir -p "${build_subdir}"
    cd "${build_subdir}"
    
    local cmake_args=(
        "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}"
        "-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}"
        "-DCMAKE_PREFIX_PATH=${SYSROOT}"
    )
    
    if [[ "${CROSS_COMPILE}" == "true" ]]; then
        cmake_args+=("-DCMAKE_TOOLCHAIN_FILE=${PROJECT_ROOT}/cmake/toolchain-${TARGET_ARCH}.cmake")
    fi
    
    if [[ "${VERBOSE_BUILD}" == "true" ]]; then
        cmake_args+=("-DCMAKE_VERBOSE_MAKEFILE=ON")
    fi
    
    log "INFO" "CMake 설정: ${component}"
    log "DEBUG" "cmake ${cmake_args[*]} ${component_dir}"
    
    if ! cmake "${cmake_args[@]}" "${component_dir}"; then
        log "ERROR" "CMake 설정 실패: ${component}"
        return 1
    fi
    
    return 0
}

# 컴포넌트 빌드
build_component() {
    local component=$1
    local component_dir="${PROJECT_ROOT}/src/${component}"
    local build_subdir="${BUILD_DIR}/${component}"
    
    log "INFO" "빌드 중: ${component}"
    
    if [[ ! -d "${component_dir}" ]]; then
        log "ERROR" "컴포넌트 디렉토리를 찾을 수 없습니다: ${component_dir}"
        return 1
    fi
    
    # CMakeLists.txt 확인
    if [[ -f "${component_dir}/CMakeLists.txt" ]]; then
        if ! setup_cmake_build "${component}"; then
            return 1
        fi
        
        cd "${build_subdir}"
        if ! make -j"${PARALLEL_JOBS}"; then
            log "ERROR" "빌드 실패: ${component}"
            return 1
        fi
        
    # Makefile 확인
    elif [[ -f "${component_dir}/Makefile" ]]; then
        cd "${component_dir}"
        if ! make -j"${PARALLEL_JOBS}"; then
            log "ERROR" "빌드 실패: ${component}"
            return 1
        fi
        
    # 직접 컴파일
    else
        cd "${component_dir}"
        
        # 소스 파일 찾기
        local sources=($(find . -name "*.c" -o -name "*.cpp" -o -name "*.cc"))
        if [[ ${#sources[@]} -eq 0 ]]; then
            log "WARN" "소스 파일을 찾을 수 없습니다: ${component}"
            return 0
        fi
        
        # 간단한 빌드 규칙
        local output_name="${component}"
        local objects=()
        
        for source in "${sources[@]}"; do
            local object="${source%.*}.o"
            objects+=("${object}")
            
            if [[ "${source}" == *.c ]]; then
                if ! ${CC} ${CFLAGS} -c "${source}" -o "${object}"; then
                    log "ERROR" "컴파일 실패: ${source}"
                    return 1
                fi
            else
                if ! ${CXX} ${CXXFLAGS} -c "${source}" -o "${object}"; then
                    log "ERROR" "컴파일 실패: ${source}"
                    return 1
                fi
            fi
        done
        
        # 링크
        if ! ${CXX} ${LDFLAGS} "${objects[@]}" -o "${output_name}"; then
            log "ERROR" "링크 실패: ${component}"
            return 1
        fi
    fi
    
    log "INFO" "빌드 완료: ${component}"
    return 0
}

# 컴포넌트 설치
install_component() {
    local component=$1
    local build_subdir="${BUILD_DIR}/${component}"
    
    log "INFO" "설치 중: ${component}"
    
    if [[ -f "${build_subdir}/Makefile" ]]; then
        cd "${build_subdir}"
        if ! make install; then
            log "ERROR" "설치 실패: ${component}"
            return 1
        fi
    else
        log "WARN" "설치 규칙을 찾을 수 없습니다: ${component}"
    fi
    
    log "INFO" "설치 완료: ${component}"
    return 0
}

# 컴포넌트 테스트
test_component() {
    local component=$1
    local build_subdir="${BUILD_DIR}/${component}"
    
    if [[ "${ENABLE_TESTS}" != "true" ]]; then
        return 0
    fi
    
    log "INFO" "테스트 중: ${component}"
    
    if [[ -f "${build_subdir}/Makefile" ]]; then
        cd "${build_subdir}"
        if make test >/dev/null 2>&1; then
            log "INFO" "테스트 통과: ${component}"
        else
            log "WARN" "테스트 실패: ${component}"
        fi
    fi
    
    return 0
}

# 커널 모듈 빌드
build_kernel() {
    log "INFO" "=== 커널 모듈 빌드 ==="
    
    local kernel_dir="${PROJECT_ROOT}/src/kernel"
    if [[ ! -d "${kernel_dir}" ]]; then
        log "ERROR" "커널 소스 디렉토리를 찾을 수 없습니다: ${kernel_dir}"
        return 1
    fi
    
    cd "${kernel_dir}"
    
    # 커널 빌드 설정
    make -j"${PARALLEL_JOBS}" modules
    make -j"${PARALLEL_JOBS}"
    
    if [[ "${ENABLE_INSTALL}" == "true" ]]; then
        make modules_install
        make install
    fi
    
    log "INFO" "커널 모듈 빌드 완료"
    return 0
}

# 패키지 관리자 빌드
build_packages() {
    log "INFO" "=== 패키지 관리자 빌드 ==="
    
    if ! build_component "packages"; then
        return 1
    fi
    
    if [[ "${ENABLE_INSTALL}" == "true" ]]; then
        install_component "packages"
    fi
    
    test_component "packages"
    
    log "INFO" "패키지 관리자 빌드 완료"
    return 0
}

# 설치 프로그램 빌드
build_installer() {
    log "INFO" "=== 설치 프로그램 빌드 ==="
    
    if ! build_component "installer"; then
        return 1
    fi
    
    if [[ "${ENABLE_INSTALL}" == "true" ]]; then
        install_component "installer"
    fi
    
    test_component "installer"
    
    log "INFO" "설치 프로그램 빌드 완료"
    return 0
}

# 시스템 도구 빌드
build_tools() {
    log "INFO" "=== 시스템 도구 빌드 ==="
    
    if ! build_component "tools"; then
        return 1
    fi
    
    if [[ "${ENABLE_INSTALL}" == "true" ]]; then
        install_component "tools"
    fi
    
    test_component "tools"
    
    log "INFO" "시스템 도구 빌드 완료"
    return 0
}

# 모든 컴포넌트 빌드
build_all() {
    log "INFO" "=== 모든 컴포넌트 빌드 ==="
    
    local components=("packages" "installer" "tools")
    local failed_components=()
    
    for component in "${components[@]}"; do
        if ! build_component "${component}"; then
            failed_components+=("${component}")
        fi
    done
    
    # 설치
    if [[ "${ENABLE_INSTALL}" == "true" ]]; then
        for component in "${components[@]}"; do
            if [[ ! " ${failed_components[*]} " =~ " ${component} " ]]; then
                install_component "${component}"
            fi
        done
    fi
    
    # 테스트
    for component in "${components[@]}"; do
        if [[ ! " ${failed_components[*]} " =~ " ${component} " ]]; then
            test_component "${component}"
        fi
    done
    
    if [[ ${#failed_components[@]} -gt 0 ]]; then
        log "ERROR" "빌드 실패한 컴포넌트:"
        for component in "${failed_components[@]}"; do
            log "ERROR" "  - ${component}"
        done
        return 1
    fi
    
    log "INFO" "모든 컴포넌트 빌드 완료"
    return 0
}

# 패키징
create_package() {
    log "INFO" "=== 패키징 ==="
    
    local package_name="massive-os"
    local package_version="1.0.0"
    local package_file="${BUILD_DIR}/${package_name}-${package_version}.tar.gz"
    
    cd "${BUILD_DIR}"
    
    # 패키지 파일 생성
    tar -czf "${package_file}" -C "${INSTALL_PREFIX}" .
    
    # 체크섬 생성
    sha256sum "${package_file}" > "${package_file}.sha256"
    
    log "INFO" "패키지 생성 완료: ${package_file}"
    log "INFO" "체크섬: $(cat "${package_file}.sha256")"
    
    return 0
}

# 빌드 통계
show_build_stats() {
    log "INFO" "=== 빌드 통계 ==="
    
    local build_time=$(date '+%Y-%m-%d %H:%M:%S')
    local build_duration=$((${SECONDS} / 60))
    
    log "INFO" "빌드 시간: ${build_time}"
    log "INFO" "빌드 소요: ${build_duration}분"
    log "INFO" "빌드 타입: ${BUILD_TYPE}"
    log "INFO" "빌드 타겟: ${BUILD_TARGET}"
    log "INFO" "병렬 작업: ${PARALLEL_JOBS}"
    
    # 빌드 결과 크기
    if [[ -d "${BUILD_DIR}" ]]; then
        local build_size=$(du -sh "${BUILD_DIR}" | cut -f1)
        log "INFO" "빌드 크기: ${build_size}"
    fi
    
    # 설치된 파일 수
    if [[ -d "${INSTALL_PREFIX}" ]]; then
        local file_count=$(find "${INSTALL_PREFIX}" -type f | wc -l)
        log "INFO" "설치된 파일: ${file_count}개"
    fi
    
    log "INFO" "빌드 통계 완료"
}

# 메인 함수
main() {
    local start_time=$(date +%s)
    
    log "INFO" "Massive OS 빌드 시스템 v${SCRIPT_VERSION}"
    log "INFO" "빌드 시작: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 인자 파싱
    parse_arguments "$@"
    
    # 환경 설정
    setup_environment
    
    # 빌드 정리
    if [[ "${CLEAN_BUILD}" == "true" ]]; then
        clean_build
        if [[ "${BUILD_TARGET}" == "clean" ]]; then
            exit 0
        fi
    fi
    
    # 의존성 체크
    check_dependencies
    
    # 타겟별 빌드
    case $BUILD_TARGET in
        "all")
            build_all
            ;;
        "kernel")
            build_kernel
            ;;
        "packages")
            build_packages
            ;;
        "installer")
            build_installer
            ;;
        "tools")
            build_tools
            ;;
        "tests")
            build_all
            ;;
        "clean")
            clean_build
            ;;
        "install")
            build_all
            ;;
        "package")
            build_all
            create_package
            ;;
        *)
            log "ERROR" "알 수 없는 빌드 타겟: ${BUILD_TARGET}"
            exit 1
            ;;
    esac
    
    # 빌드 통계
    local end_time=$(date +%s)
    SECONDS=$((end_time - start_time))
    show_build_stats
    
    log "INFO" "빌드 완료: $(date '+%Y-%m-%d %H:%M:%S')"
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
