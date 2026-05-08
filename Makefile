# UnifiedArch OS Master Makefile
# 메인 빌드 시스템 - 전체 OS 빌드 및 패키징 관리

# 프로젝트 정보
PROJECT_NAME := UnifiedArch
VERSION := 1.0.0
BUILD_DATE := $(shell date +%Y%m%d)
BUILD_ID := $(PROJECT_NAME)-$(VERSION)-$(BUILD_DATE)

# 디렉토리 구조
SRC_DIR := src
BUILD_DIR := build
TESTS_DIR := tests
DOCS_DIR := docs
VARIANTS_DIR := variants
PACKAGES_DIR := packages
KERNEL_DIR := $(SRC_DIR)/kernel
INSTALLER_DIR := $(SRC_DIR)/installer
TOOLS_DIR := $(SRC_DIR)/tools
CONFIG_DIR := $(SRC_DIR)/config

# 빌드 타겟
.PHONY: all clean kernel modules installer tools packages variants test docs install iso help

# 기본 타겟
all: kernel modules installer tools packages

# 커널 모듈 빌드
kernel:
	@echo "커널 모듈 빌드 중..."
	$(MAKE) -C $(KERNEL_DIR) all

# 개별 모듈 빌드
modules:
	@echo "커널 모듈 빌드 중..."
	$(MAKE) -C $(KERNEL_DIR) modules

# 설치 프로그램 빌드
installer:
	@echo "설치 프로그램 빌드 중..."
	$(MAKE) -C $(INSTALLER_DIR) all

# 관리 도구 빌드
tools:
	@echo "관리 도구 빌드 중..."
	$(MAKE) -C $(TOOLS_DIR) all

# 패키지 빌드
packages:
	@echo "패키지 빌드 중..."
	$(MAKE) -C $(SRC_DIR)/packages all

# OS 변형 버전 빌드
variants: standard minimal enterprise gaming

standard:
	@echo "Standard 변형 빌드 중..."
	$(MAKE) -C $(VARIANTS_DIR)/standard VARIANT=standard

minimal:
	@echo "Minimal 변형 빌드 중..."
	$(MAKE) -C $(VARIANTS_DIR)/minimal VARIANT=minimal

enterprise:
	@echo "Enterprise 변형 빌드 중..."
	$(MAKE) -C $(VARIANTS_DIR)/enterprise VARIANT=enterprise

gaming:
	@echo "Gaming 변형 빌드 중..."
	$(MAKE) -C $(VARIANTS_DIR)/gaming VARIANT=gaming

# 테스트 실행
test:
	@echo "테스트 실행 중..."
	$(MAKE) -C $(TESTS_DIR) test

# 문서 생성
docs:
	@echo "문서 생성 중..."
	$(MAKE) -C $(DOCS_DIR) docs

# ISO 이미지 생성
iso: all
	@echo "ISO 이미지 생성 중..."
	@mkdir -p $(BUILD_DIR)/iso
	@./scripts/build-iso.sh $(BUILD_ID)

# 설치
install: all
	@echo "설치 중..."
	@./scripts/install.sh

# 클린
clean:
	@echo "정리 중..."
	$(MAKE) -C $(KERNEL_DIR) clean
	$(MAKE) -C $(INSTALLER_DIR) clean
	$(MAKE) -C $(TOOLS_DIR) clean
	$(MAKE) -C $(SRC_DIR)/packages clean
	$(MAKE) -C $(VARIANTS_DIR)/standard clean
	$(MAKE) -C $(VARIANTS_DIR)/minimal clean
	$(MAKE) -C $(VARIANTS_DIR)/enterprise clean
	$(MAKE) -C $(VARIANTS_DIR)/gaming clean
	$(MAKE) -C $(TESTS_DIR) clean
	@rm -rf $(BUILD_DIR)
	@rm -f *.iso *.tar.gz

# 개발 환경 설정
dev-setup:
	@echo "개발 환경 설정 중..."
	@./scripts/dev-setup.sh

# 코드 스타일 검사
lint:
	@echo "코드 스타일 검사 중..."
	@./scripts/lint.sh

# 정적 분석
analyze:
	@echo "정적 분석 중..."
	@./scripts/analyze.sh

# 보안 검사
security-scan:
	@echo "보안 검사 중..."
	@./scripts/security-scan.sh

# 성능 벤치마크
benchmark:
	@echo "성능 벤치마크 중..."
	@./scripts/benchmark.sh

# 릴리스 준비
release: clean all test docs
	@echo "릴리스 준비 중..."
	@mkdir -p $(BUILD_DIR)/release
	@tar -czf $(BUILD_DIR)/release/$(BUILD_ID).tar.gz \
		--exclude=$(BUILD_DIR) \
		--exclude=.git \
		--exclude=*.log \
		.
	@cd $(BUILD_DIR)/release && sha256sum $(BUILD_ID).tar.gz > $(BUILD_ID).tar.gz.sha256

# 도움말
help:
	@echo "UnifiedArch OS 빌드 시스템"
	@echo ""
	@echo "사용 가능한 타겟:"
	@echo "  all          - 모든 컴포넌트 빌드"
	@echo "  kernel       - 커널 모듈 빌드"
	@echo "  modules      - 개별 모듈 빌드"
	@echo "  installer    - 설치 프로그램 빌드"
	@echo "  tools        - 관리 도구 빌드"
	@echo "  packages     - 패키지 빌드"
	@echo "  variants     - 모든 변형 버전 빌드"
	@echo "  standard     - Standard 변형 빌드"
	@echo "  minimal      - Minimal 변형 빌드"
	@echo "  enterprise   - Enterprise 변형 빌드"
	@echo "  gaming       - Gaming 변형 빌드"
	@echo "  test         - 테스트 실행"
	@echo "  docs         - 문서 생성"
	@echo "  iso          - ISO 이미지 생성"
	@echo "  install      - 설치"
	@echo "  clean        - 빌드 파일 정리"
	@echo "  dev-setup    - 개발 환경 설정"
	@echo "  lint         - 코드 스타일 검사"
	@echo "  analyze      - 정적 분석"
	@echo "  security-scan - 보안 검사"
	@echo "  benchmark    - 성능 벤치마크"
	@echo "  release      - 릴리스 준비"
	@echo "  help         - 이 도움말 표시"
	@echo ""
	@echo "변수:"
	@echo "  VERSION      - 버전 ($(VERSION))"
	@echo "  BUILD_DATE   - 빌드 날짜 ($(BUILD_DATE))"
	@echo "  BUILD_ID     - 빌드 ID ($(BUILD_ID))"
