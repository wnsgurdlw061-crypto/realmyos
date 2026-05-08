#!/bin/bash
# UnifiedArch OS 전체 테스트 스크립트
# 실제로 동작하는 모든 컴포넌트 테스트

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
TEST_DATE=$(date +%Y%m%d)

# 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
TEST_DIR="$SCRIPT_DIR"
RESULTS_DIR="$TEST_DIR/results"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 테스트 결과 변수
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

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

log_test() {
    echo -e "${PURPLE}[TEST]${NC} $1"
}

log_result() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $message"
            ((PASSED_TESTS++))
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $message"
            ((FAILED_TESTS++))
            ;;
        "SKIP")
            echo -e "${YELLOW}[SKIP]${NC} $message"
            ((SKIPPED_TESTS++))
            ;;
    esac
    ((TOTAL_TESTS++))
}

# 테스트 초기화
init_tests() {
    log_info "테스트 초기화 중..."
    
    # 결과 디렉토리 생성
    mkdir -p "$RESULTS_DIR"
    
    # 테스트 로그 파일
    TEST_LOG="$RESULTS_DIR/test-$TEST_DATE.log"
    echo "UnifiedArch OS 테스트 결과 - $TEST_DATE" > "$TEST_LOG"
    echo "========================================" >> "$TEST_LOG"
    
    # 테스트 환경 확인
    if [[ $EUID -eq 0 ]]; then
        log_warning "루트 권한으로 실행 중 - 일부 테스트가 제한될 수 있습니다"
    fi
    
    log_success "테스트 초기화 완료"
}

# 파일 구조 테스트
test_project_structure() {
    log_test "프로젝트 구조 테스트"
    
    local required_dirs=("src" "docs" "build" "tests" "include" "etc")
    local required_files=("README.md" "Makefile" "build.sh")
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$PROJECT_ROOT/$dir" ]]; then
            log_result "PASS" "디렉토리 존재: $dir"
        else
            log_result "FAIL" "디렉토리 없음: $dir"
        fi
    done
    
    for file in "${required_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            log_result "PASS" "파일 존재: $file"
        else
            log_result "FAIL" "파일 없음: $file"
        fi
    done
    
    # 소스 파일 확인
    local source_files=("src/kernel/emergency_response.c" "src/kernel/btrfs_integration.c" 
                       "src/kernel/anomaly_detector.c" "src/installer/install.sh")
    
    for file in "${source_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            log_result "PASS" "소스 파일 존재: $file"
        else
            log_result "FAIL" "소스 파일 없음: $file"
        fi
    done
}

# 커널 모듈 테스트
test_kernel_modules() {
    log_test "커널 모듈 테스트"
    
    local kernel_dir="$PROJECT_ROOT/src/kernel"
    
    # 커널 헤더 확인
    if [[ -d "/lib/modules/$(uname -r)/build" ]]; then
        log_result "PASS" "커널 헤더 존재"
        
        # 모듈 컴파일 테스트
        cd "$kernel_dir"
        if make clean >/dev/null 2>&1; then
            log_result "PASS" "커널 모듈 클린 성공"
            
            if make -j$(nproc) >/dev/null 2>&1; then
                log_result "PASS" "커널 모듈 컴파일 성공"
                
                # 모듈 파일 확인
                if ls *.ko >/dev/null 2>&1; then
                    log_result "PASS" "커널 모듈 파일 생성됨"
                    
                    # 모듈 정보 확인
                    for module in *.ko; do
                        if modinfo "$module" >/dev/null 2>&1; then
                            log_result "PASS" "모듈 정보 확인: $module"
                        else
                            log_result "FAIL" "모듈 정보 오류: $module"
                        fi
                    done
                else
                    log_result "FAIL" "커널 모듈 파일 없음"
                fi
            else
                log_result "FAIL" "커널 모듈 컴파일 실패"
            fi
        else
            log_result "FAIL" "커널 모듈 클린 실패"
        fi
        cd "$PROJECT_ROOT"
    else
        log_result "SKIP" "커널 헤더 없음 - 커널 모듈 테스트 건너뜀"
    fi
}

# 설치 스크립트 테스트
test_installer() {
    log_test "설치 스크립트 테스트"
    
    local installer_script="$PROJECT_ROOT/src/installer/install.sh"
    
    # 스크립트 존재 확인
    if [[ -f "$installer_script" ]]; then
        log_result "PASS" "설치 스크립트 존재"
        
        # 실행 권한 확인
        if [[ -x "$installer_script" ]]; then
            log_result "PASS" "설치 스크립트 실행 권한 있음"
        else
            log_result "FAIL" "설치 스크립트 실행 권한 없음"
        fi
        
        # 문법 검사
        if bash -n "$installer_script" 2>/dev/null; then
            log_result "PASS" "설치 스크립트 문법 정상"
        else
            log_result "FAIL" "설치 스크립트 문법 오류"
        fi
        
        # 필수 함수 확인
        local required_functions=("check_requirements" "detect_hardware" "partition_disk" 
                                "mount_filesystems" "install_base_system" "configure_system")
        
        for func in "${required_functions[@]}"; do
            if grep -q "^$func()" "$installer_script"; then
                log_result "PASS" "함수 존재: $func"
            else
                log_result "FAIL" "함수 없음: $func"
            fi
        done
        
        # shellcheck 검사 (설치된 경우)
        if command -v shellcheck >/dev/null 2>&1; then
            if shellcheck "$installer_script" >/dev/null 2>&1; then
                log_result "PASS" "shellcheck 검사 통과"
            else
                log_result "FAIL" "shellcheck 검사 실패"
            fi
        else
            log_result "SKIP" "shellcheck 없음 - 검사 건너뜀"
        fi
    else
        log_result "FAIL" "설치 스크립트 없음"
    fi
}

# 빌드 시스템 테스트
test_build_system() {
    log_test "빌드 시스템 테스트"
    
    local build_script="$PROJECT_ROOT/build.sh"
    local main_makefile="$PROJECT_ROOT/Makefile"
    
    # 빌드 스크립트 테스트
    if [[ -f "$build_script" ]]; then
        log_result "PASS" "빌드 스크립트 존재"
        
        if [[ -x "$build_script" ]]; then
            log_result "PASS" "빌드 스크립트 실행 권한 있음"
        else
            log_result "FAIL" "빌드 스크립트 실행 권한 없음"
        fi
        
        # 문법 검사
        if bash -n "$build_script" 2>/dev/null; then
            log_result "PASS" "빌드 스크립트 문법 정상"
        else
            log_result "FAIL" "빌드 스크립트 문법 오류"
        fi
    else
        log_result "FAIL" "빌드 스크립트 없음"
    fi
    
    # Makefile 테스트
    if [[ -f "$main_makefile" ]]; then
        log_result "PASS" "메인 Makefile 존재"
        
        # Makefile 문법 검사
        if make -n -f "$main_makefile" >/dev/null 2>&1; then
            log_result "PASS" "Makefile 문법 정상"
        else
            log_result "FAIL" "Makefile 문법 오류"
        fi
        
        # 타겟 확인
        local required_targets=("all" "clean" "kernel" "installer" "help")
        for target in "${required_targets[@]}"; do
            if grep -q "^$target:" "$main_makefile"; then
                log_result "PASS" "Makefile 타겟 존재: $target"
            else
                log_result "FAIL" "Makefile 타겟 없음: $target"
            fi
        done
    else
        log_result "FAIL" "메인 Makefile 없음"
    fi
}

# 설정 파일 테스트
test_configuration() {
    log_test "설정 파일 테스트"
    
    # YAML 설정 파일 테스트
    local config_files=("src/config/unifiedarch.yaml" "src/packages/package-profiles.yaml")
    
    for config_file in "${config_files[@]}"; do
        local full_path="$PROJECT_ROOT/$config_file"
        if [[ -f "$full_path" ]]; then
            log_result "PASS" "설정 파일 존재: $config_file"
            
            # YAML 문법 검사 (yq가 있는 경우)
            if command -v yq >/dev/null 2>&1; then
                if yq eval '.' "$full_path" >/dev/null 2>&1; then
                    log_result "PASS" "YAML 문법 정상: $config_file"
                else
                    log_result "FAIL" "YAML 문법 오류: $config_file"
                fi
            else
                log_result "SKIP" "yq 없음 - YAML 검사 건너뜀"
            fi
        else
            log_result "FAIL" "설정 파일 없음: $config_file"
        fi
    done
    
    # 헤더 파일 테스트
    local header_files=("include/network_security.h" "include/security_tools.h")
    
    for header_file in "${header_files[@]}"; do
        local full_path="$PROJECT_ROOT/$header_file"
        if [[ -f "$full_path" ]]; then
            log_result "PASS" "헤더 파일 존재: $header_file"
            
            # C 문법 검사
            if gcc -fsyntax-only -I"$PROJECT_ROOT/include" "$full_path" 2>/dev/null; then
                log_result "PASS" "헤더 파일 문법 정상: $header_file"
            else
                log_result "FAIL" "헤더 파일 문법 오류: $header_file"
            fi
        else
            log_result "FAIL" "헤더 파일 없음: $header_file"
        fi
    done
}

# 문서 테스트
test_documentation() {
    log_test "문서 테스트"
    
    local docs_dir="$PROJECT_ROOT/docs"
    
    # 문서 디렉토리 확인
    if [[ -d "$docs_dir" ]]; then
        log_result "PASS" "문서 디렉토리 존재"
        
        # 마크다운 파일 확인
        local md_files=("$docs_dir/phase1-architecture.md" "$docs_dir/phase2-installation.md")
        
        for md_file in "${md_files[@]}"; do
            if [[ -f "$md_file" ]]; then
                log_result "PASS" "문서 파일 존재: $(basename "$md_file")"
                
                # 마크다운 문법 검사 (pandoc이 있는 경우)
                if command -v pandoc >/dev/null 2>&1; then
                    if pandoc -f markdown -t html "$md_file" >/dev/null 2>&1; then
                        log_result "PASS" "마크다운 문법 정상: $(basename "$md_file")"
                    else
                        log_result "FAIL" "마크다운 문법 오류: $(basename "$md_file")"
                    fi
                else
                    log_result "SKIP" "pandoc 없음 - 마크다운 검사 건너뜀"
                fi
            else
                log_result "FAIL" "문서 파일 없음: $(basename "$md_file")"
            fi
        done
    else
        log_result "FAIL" "문서 디렉토리 없음"
    fi
    
    # README 테스트
    local readme_file="$PROJECT_ROOT/README.md"
    if [[ -f "$readme_file" ]]; then
        log_result "PASS" "README.md 존재"
        
        # README 내용 확인
        if grep -q "UnifiedArch" "$readme_file"; then
            log_result "PASS" "README에 프로젝트 이름 포함"
        else
            log_result "FAIL" "README에 프로젝트 이름 없음"
        fi
    else
        log_result "FAIL" "README.md 없음"
    fi
}

# 통합 테스트
test_integration() {
    log_test "통합 테스트"
    
    # 빌드 테스트
    log_info "전체 빌드 테스트 중..."
    
    if "$PROJECT_ROOT/build.sh" clean >/dev/null 2>&1; then
        log_result "PASS" "빌드 클린 성공"
        
        if "$PROJECT_ROOT/build.sh" docs >/dev/null 2>&1; then
            log_result "PASS" "문서 빌드 성공"
            
            if "$PROJECT_ROOT/build.sh" installer >/dev/null 2>&1; then
                log_result "PASS" "설치 프로그램 빌드 성공"
                
                # 빌드 결과 확인
                if [[ -d "$BUILD_DIR/installer" ]]; then
                    log_result "PASS" "빌드 결과 존재"
                    
                    if [[ -f "$BUILD_DIR/installer/install.sh" ]]; then
                        log_result "PASS" "설치 스크립트 빌드됨"
                    else
                        log_result "FAIL" "설치 스크립트 빌드되지 않음"
                    fi
                else
                    log_result "FAIL" "빌드 결과 없음"
                fi
            else
                log_result "FAIL" "설치 프로그램 빌드 실패"
            fi
        else
            log_result "FAIL" "문서 빌드 실패"
        fi
    else
        log_result "FAIL" "빌드 클린 실패"
    fi
}

# 성능 테스트
test_performance() {
    log_test "성능 테스트"
    
    # 빌드 시간 측정
    local start_time=$(date +%s)
    
    if "$PROJECT_ROOT/build.sh" docs >/dev/null 2>&1; then
        local end_time=$(date +%s)
        local build_time=$((end_time - start_time))
        
        if [[ $build_time -lt 60 ]]; then
            log_result "PASS" "빌드 시간 양호 (${build_time}초)"
        else
            log_result "WARN" "빌드 시간 김 (${build_time}초)"
        fi
    else
        log_result "FAIL" "성능 테스트 실패"
    fi
    
    # 메모리 사용량 측정
    if command -v /usr/bin/time >/dev/null 2>&1; then
        local memory_result=$(/usr/bin/time -f "%M" "$PROJECT_ROOT/build.sh" docs 2>&1 >/dev/null)
        if [[ -n "$memory_result" ]]; then
            local memory_kb=$((memory_result))
            if [[ $memory_kb -lt 100000 ]]; then  # 100MB 미만
                log_result "PASS" "메모리 사용량 양호 (${memory_kb}KB)"
            else
                log_result "WARN" "메모리 사용량 높음 (${memory_kb}KB)"
            fi
        fi
    else
        log_result "SKIP" "/usr/bin/time 없음 - 메모리 테스트 건너뜀"
    fi
}

# 보안 테스트
test_security() {
    log_test "보안 테스트"
    
    # 파일 권한 확인
    local executable_files=("$PROJECT_ROOT/build.sh" "$PROJECT_ROOT/src/installer/install.sh")
    
    for file in "${executable_files[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ -x "$file" ]]; then
                log_result "PASS" "실행 권한 있음: $(basename "$file")"
            else
                log_result "FAIL" "실행 권한 없음: $(basename "$file")"
            fi
        fi
    done
    
    # 민감한 파일 권한 확인
    local sensitive_files=("$PROJECT_ROOT/src/installer/install.sh")
    
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            local perms=$(stat -c "%a" "$file")
            if [[ "$perms" -le 755 ]]; then
                log_result "PASS" "안전한 권한: $(basename "$file") ($perms)"
            else
                log_result "WARN" "너무 열린 권한: $(basename "$file") ($perms)"
            fi
        fi
    done
    
    # 보안 스캐닝 (semgrep이 있는 경우)
    if command -v semgrep >/dev/null 2>&1; then
        if semgrep --config=auto "$PROJECT_ROOT/src" >/dev/null 2>&1; then
            log_result "PASS" "semgrep 보안 검사 통과"
        else
            log_result "WARN" "semgrep 보안 검사 경고 있음"
        fi
    else
        log_result "SKIP" "semgrep 없음 - 보안 검사 건너뜀"
    fi
}

# 테스트 결과 요약
show_results() {
    echo ""
    echo -e "${CYAN}=== 테스트 결과 요약 ===${NC}"
    echo "총 테스트: $TOTAL_TESTS"
    echo -e "통과: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "실패: ${RED}$FAILED_TESTS${NC}"
    echo -e "건너뜀: ${YELLOW}$SKIPPED_TESTS${NC}"
    
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    echo "성공률: ${success_rate}%"
    
    # 로그 파일에 결과 저장
    echo "" >> "$TEST_LOG"
    echo "테스트 결과 요약:" >> "$TEST_LOG"
    echo "총 테스트: $TOTAL_TESTS" >> "$TEST_LOG"
    echo "통과: $PASSED_TESTS" >> "$TEST_LOG"
    echo "실패: $FAILED_TESTS" >> "$TEST_LOG"
    echo "건너뜀: $SKIPPED_TESTS" >> "$TEST_LOG"
    echo "성공률: ${success_rate}%" >> "$TEST_LOG"
    
    # 종료 코드 설정
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo ""
        log_error "테스트 실패! 실패한 테스트가 있습니다."
        return 1
    else
        echo ""
        log_success "모든 테스트 통과!"
        return 0
    fi
}

# 메인 함수
main() {
    local test_type="${1:-all}"
    
    echo -e "${CYAN}"
    cat << 'EOF'
 ____  _ _ _   _                     _      
| __ )(_) | | | | __ _ _ __   __ _ (_)_ __ 
|  _ \| | | |_| |/ _` | '_ \ / _` || | '_ \
| |_) | | |  _  | (_| | | | | (_| || | | | |
|____/|_|_|_| |_|\__,_|_| |_|\__,_||_|_| |_|
                                              
          전체 테스트 시스템 v1.0
EOF
    echo -e "${NC}"
    
    init_tests
    
    case "$test_type" in
        "all")
            test_project_structure
            test_kernel_modules
            test_installer
            test_build_system
            test_configuration
            test_documentation
            test_integration
            test_performance
            test_security
            ;;
        "structure")
            test_project_structure
            ;;
        "kernel")
            test_kernel_modules
            ;;
        "installer")
            test_installer
            ;;
        "build")
            test_build_system
            ;;
        "config")
            test_configuration
            ;;
        "docs")
            test_documentation
            ;;
        "integration")
            test_integration
            ;;
        "performance")
            test_performance
            ;;
        "security")
            test_security
            ;;
        *)
            log_error "알 수 없는 테스트 타입: $test_type"
            echo "사용 가능한 테스트: all, structure, kernel, installer, build, config, docs, integration, performance, security"
            exit 1
            ;;
    esac
    
    show_results
}

# 스크립트 실행
main "$@"
