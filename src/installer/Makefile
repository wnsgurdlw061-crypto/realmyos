# UnifiedArch OS Installer Makefile
# 설치 프로그램 빌드 시스템

# 설치 프로그램 정보
INSTALLER_NAME := unifiedarch-installer
VERSION := 1.0.0

# 디렉토리 구조
SRC_DIR := .
BUILD_DIR := ../../build/installer
CONFIG_DIR := ../config
SCRIPTS_DIR := scripts
TEMPLATES_DIR := templates
TESTS_DIR := tests

# 소스 파일
SOURCES := install-script.sh
SCRIPTS := $(wildcard $(SCRIPTS_DIR)/*.sh)
TEMPLATES := $(wildcard $(TEMPLATES_DIR)/*)

# 빌드 타겟
.PHONY: all install uninstall test clean package docs help

# 기본 타겟
all: $(BUILD_DIR) $(SOURCES) $(SCRIPTS)

# 빌드 디렉토리 생성
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/scripts
	@mkdir -p $(BUILD_DIR)/templates
	@mkdir -p $(BUILD_DIR)/config

# 스크립트 복사 및 설정
$(BUILD_DIR)/install-script.sh: install-script.sh
	@echo "설치 스크립트 복사 중..."
	@cp install-script.sh $@
	@chmod +x $@
	@sed -i 's|CONFIG_FILE="/etc/unifiedarch/config.yaml"|CONFIG_FILE="$(CONFIG_DIR)/unifiedarch.yaml"|g' $@

# 스크립트 파일 복사
scripts: $(SCRIPTS)
	@echo "보조 스크립트 복사 중..."
	@for script in $(SCRIPTS); do \
		cp $$script $(BUILD_DIR)/scripts/; \
		chmod +x $(BUILD_DIR)/scripts/$$(basename $$script); \
	done

# 템플릿 파일 복사
templates: $(TEMPLATES)
	@echo "템플릿 파일 복사 중..."
	@for template in $(TEMPLATES); do \
		cp $$template $(BUILD_DIR)/templates/; \
	done

# 설정 파일 복사
config: $(CONFIG_DIR)/unifiedarch.yaml
	@echo "설정 파일 복사 중..."
	@cp $(CONFIG_DIR)/unifiedarch.yaml $(BUILD_DIR)/config/

# 완전한 빌드
all: $(BUILD_DIR)/install-script.sh scripts templates config

# 설치
install: all
	@echo "설치 프로그램 설치 중..."
	@mkdir -p /usr/share/$(INSTALLER_NAME)
	@mkdir -p /usr/bin
	@cp -r $(BUILD_DIR)/* /usr/share/$(INSTALLER_NAME)/
	@ln -sf /usr/share/$(INSTALLER_NAME)/install-script.sh /usr/bin/$(INSTALLER_NAME)
	@echo "설치 완료: /usr/bin/$(INSTALLER_NAME)"

# 제거
uninstall:
	@echo "설치 프로그램 제거 중..."
	@rm -rf /usr/share/$(INSTALLER_NAME)
	@rm -f /usr/bin/$(INSTALLER_NAME)
	@echo "제거 완료"

# 테스트
test: all
	@echo "설치 프로그램 테스트 중..."
	@if [ -d $(TESTS_DIR) ]; then \
		$(MAKE) -C $(TESTS_DIR) test; \
	else \
		echo "테스트 디렉토리 없음"; \
	fi

# 클린
clean:
	@echo "정리 중..."
	@rm -rf $(BUILD_DIR)

# 패키징
package: all
	@echo "설치 프로그램 패키징 중..."
	@cd $(BUILD_DIR) && tar -czf $(INSTALLER_NAME)-$(VERSION).tar.gz *
	@mkdir -p ../../build/packages
	@cp $(BUILD_DIR)/$(INSTALLER_NAME)-$(VERSION).tar.gz ../../build/packages/

# 문서 생성
docs:
	@echo "문서 생성 중..."
	@mkdir -p $(BUILD_DIR)/docs
	@for script in $(SOURCES) $(SCRIPTS); do \
		if [ -f "$$script" ]; then \
			basename=$$(basename $$script .sh); \
			echo "문서 생성: $$basename"; \
			groff -man -Thtml $$script > $(BUILD_DIR)/docs/$$basename.html 2>/dev/null || true; \
		fi; \
	done

# 코드 스타일 검사
lint:
	@echo "코드 스타일 검사 중..."
	@for script in $(SOURCES) $(SCRIPTS); do \
		if [ -f "$$script" ]; then \
			echo "검사: $$script"; \
			shellcheck "$$script" || true; \
		fi; \
	done

# 보안 검사
security:
	@echo "보안 검사 중..."
	@for script in $(SOURCES) $(SCRIPTS); do \
		if [ -f "$$script" ]; then \
			echo "보안 검사: $$script"; \
			semgrep --config=auto "$$script" || true; \
		fi; \
	done

# 의존성 확인
deps:
	@echo "의존성 확인 중..."
	@which arch-chroot > /dev/null || (echo "arch-chroot 필요" && exit 1)
	@which pacstrap > /dev/null || (echo "pacstrap 필요" && exit 1)
	@which genfstab > /dev/null || (echo "genfstab 필요" && exit 1)
	@echo "의존성 확인 완료"

# 개발 환경 설정
dev-setup:
	@echo "개발 환경 설정 중..."
	@mkdir -p $(SCRIPTS_DIR)
	@mkdir -p $(TEMPLATES_DIR)
	@mkdir -p $(TESTS_DIR)
	@echo "#!/bin/bash" > $(SCRIPTS_DIR)/helper.sh
	@chmod +x $(SCRIPTS_DIR)/helper.sh
	@echo "개발 환경 설정 완료"

# ISO 생성 준비
prepare-iso: all
	@echo "ISO 생성 준비 중..."
	@mkdir -p ../../build/iso/unifiedarch
	@cp -r $(BUILD_DIR)/* ../../build/iso/unifiedarch/
	@cp ../../README.md ../../build/iso/ 2>/dev/null || true

# 검증
validate: all
	@echo "설치 프로그램 검증 중..."
	@bash -n $(BUILD_DIR)/install-script.sh
	@for script in $(SCRIPTS); do \
		if [ -f "$$script" ]; then \
			bash -n "$$script"; \
		fi; \
	done
	@echo "검증 완료"

# 통합 테스트
integration-test: all
	@echo "통합 테스트 중..."
	@if [ -f $(TESTS_DIR)/integration-test.sh ]; then \
		$(TESTS_DIR)/integration-test.sh $(BUILD_DIR); \
	else \
		echo "통합 테스트 스크립트 없음"; \
	fi

# 성능 테스트
benchmark: all
	@echo "성능 테스트 중..."
	@time $(BUILD_DIR)/install-script.sh --test-mode

# 릴리스 준비
release: clean all test docs package
	@echo "릴리스 준비 완료"

# 도움말
help:
	@echo "UnifiedArch 설치 프로그램 빌드 시스템"
	@echo ""
	@echo "사용 가능한 타겟:"
	@echo "  all              - 모든 컴포넌트 빌드"
	@echo "  install          - 설치 프로그램 설치"
	@echo "  uninstall        - 설치 프로그램 제거"
	@echo "  test             - 테스트 실행"
	@echo "  clean            - 빌드 파일 정리"
	@echo "  package          - 패키징"
	@echo "  docs             - 문서 생성"
	@echo "  lint             - 코드 스타일 검사"
	@echo "  security         - 보안 검사"
	@echo "  deps             - 의존성 확인"
	@echo "  dev-setup        - 개발 환경 설정"
	@echo "  prepare-iso      - ISO 생성 준비"
	@echo "  validate         - 스크립트 검증"
	@echo "  integration-test - 통합 테스트"
	@echo "  benchmark        - 성능 테스트"
	@echo "  release          - 릴리스 준비"
	@echo "  help             - 이 도움말 표시"
	@echo ""
	@echo "파일:"
	@echo "  install-script.sh - 메인 설치 스크립트"
	@echo "  scripts/          - 보조 스크립트"
	@echo "  templates/        - 설정 템플릿"
	@echo "  config/           - 설정 파일"
	@echo ""
	@echo "디렉토리:"
	@echo "  BUILD_DIR         - 빌드 출력 ($(BUILD_DIR))"
	@echo "  CONFIG_DIR        - 설정 파일 ($(CONFIG_DIR))"
