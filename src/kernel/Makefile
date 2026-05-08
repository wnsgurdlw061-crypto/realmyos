# UnifiedArch OS Kernel Modules Makefile
# 커널 모듈 빌드 시스템

# Core modules
obj-m += unifiedarch-core.o
unifiedarch-core-objs := emergency_response_fixed.o btrfs_integration.o anomaly_detector.o

# Individual modules for testing
obj-m += emergency_response_fixed.o
obj-m += btrfs_integration.o  
obj-m += anomaly_detector.o

# 커널 소스 디렉토리
KERNEL_DIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

# 컴파일 플래그
ccflags-y := -Wall -Wextra -Wno-unused-parameter
ccflags-y += -DVERSION=\"$(VERSION)\"
ccflags-y += -I$(PWD)/../../include

# 링크 플래그
ldflags-y :=

# 기본 타겟
all: modules

# 모듈 빌드
modules:
	@echo "커널 모듈 빌드 중..."
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules

# 개별 모듈 빌드
emergency_response.o: emergency_response.c
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) $@

btrfs_integration.o: btrfs_integration.c
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) $@

anomaly_detector.o: anomaly_detector.c
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) $@

# 모듈 설치
install: modules
	@echo "커널 모듈 설치 중..."
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules_install
	depmod -a

# 모듈 제거
uninstall:
	@echo "커널 모듈 제거 중..."
	@rmmod emergency_response 2>/dev/null || true
	@rmmod btrfs_integration 2>/dev/null || true
	@rmmod anomaly_detector 2>/dev/null || true
	@rm -f /lib/modules/$(shell uname -r)/extra/$(MODULE_NAME)/*.ko
	depmod -a

# 모듈 로드
load: modules
	@echo "커널 모듈 로드 중..."
	@insmod emergency_response.ko
	@insmod btrfs_integration.ko
	@insmod anomaly_detector.ko

# 모듈 언로드
unload:
	@echo "커널 모듈 언로드 중..."
	@rmmod anomaly_detector 2>/dev/null || true
	@rmmod btrfs_integration 2>/dev/null || true
	@rmmod emergency_response 2>/dev/null || true

# 모듈 상태 확인
status:
	@echo "커널 모듈 상태:"
	@lsmod | grep -E "(emergency_response|btrfs_integration|anomaly_detector)" || echo "로드된 모듈 없음"
	@echo ""
	@echo "proc 엔트리:"
	@ls -la /proc/unifiedarch_* 2>/dev/null || echo "proc 엔트리 없음"

# 모듈 정보
info:
	@echo "모듈 정보:"
	@modinfo emergency_response.ko 2>/dev/null || echo "emergency_response 모듈 없음"
	@modinfo btrfs_integration.ko 2>/dev/null || echo "btrfs_integration 모듈 없음"
	@modinfo anomaly_detector.ko 2>/dev/null || echo "anomaly_detector 모듈 없음"

# 로그 확인
logs:
	@echo "커널 로그 (최근 50줄):"
	@dmesg | tail -50 | grep -i unifiedarch || echo "UnifiedArch 로그 없음"

# 테스트
test: load
	@echo "모듈 테스트 중..."
	@./scripts/test-modules.sh

# 클린
clean:
	@echo "정리 중..."
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
	@rm -f *.o *.ko *.mod.c .*.cmd *.markers *.symvers *.order
	@rm -rf .tmp_versions

# 딥 클린
distclean: clean
	@rm -f *.symvers *.order

# 코드 스타일 검사
lint:
	@echo "코드 스타일 검사 중..."
	@for file in *.c; do \
		if [ -f "$$file" ]; then \
			echo "검사: $$file"; \
			cppcheck --enable=all --std=c99 "$$file" || true; \
		fi; \
	done

# 정적 분석
analyze:
	@echo "정적 분석 중..."
	@for file in *.c; do \
		if [ -f "$$file" ]; then \
			echo "분석: $$file"; \
			splint -weak "$$file" || true; \
		fi; \
	done

# 메모리 누수 검사
memcheck:
	@echo "메모리 누수 검사 중..."
	@valgrind --leak-check=full --show-leak-kinds=all ./test/memcheck-test || true

# 커버리지
coverage:
	@echo "커버리지 분석 중..."
	@gcov *.c
	@lcov --capture --directory . --output-file coverage.info
	@genhtml coverage.info --output-directory coverage_html

# 보안 검사
security:
	@echo "보안 검사 중..."
	@for file in *.c; do \
		if [ -f "$$file" ]; then \
			echo "보안 검사: $$file"; \
			flawfinder "$$file" || true; \
		fi; \
	done

# 문서 생성
docs:
	@echo "문서 생성 중..."
	@for file in *.c; do \
		if [ -f "$$file" ]; then \
			doxygen "$$file" || true; \
		fi; \
	done

# 패키징
package: modules
	@echo "커널 모듈 패키징 중..."
	@mkdir -p ../build/kernel
	@cp *.ko ../build/kernel/
	@cp README.md ../build/kernel/ 2>/dev/null || true
	@cd ../build/kernel && tar -czf $(MODULE_NAME)-$(VERSION).tar.gz *.ko README.md 2>/dev/null || tar -czf $(MODULE_NAME)-$(VERSION).tar.gz *.ko

# 도움말
help:
	@echo "UnifiedArch 커널 모듈 빌드 시스템"
	@echo ""
	@echo "사용 가능한 타겟:"
	@echo "  all           - 모든 모듈 빌드"
	@echo "  modules       - 모듈 빌드 (기본)"
	@echo "  install       - 모듈 설치"
	@echo "  uninstall     - 모듈 제거"
	@echo "  load          - 모듈 로드"
	@echo "  unload        - 모듈 언로드"
	@echo "  status        - 모듈 상태 확인"
	@echo "  info          - 모듈 정보"
	@echo "  logs          - 커널 로그 확인"
	@echo "  test          - 모듈 테스트"
	@echo "  clean         - 빌드 파일 정리"
	@echo "  distclean     - 완전 정리"
	@echo "  lint          - 코드 스타일 검사"
	@echo "  analyze       - 정적 분석"
	@echo "  memcheck      - 메모리 누수 검사"
	@echo "  coverage      - 커버리지 분석"
	@echo "  security      - 보안 검사"
	@echo "  docs          - 문서 생성"
	@echo "  package       - 패키징"
	@echo "  help          - 이 도움말 표시"
	@echo ""
	@echo "모듈:"
	@echo "  emergency_response - 비상 응답 시스템"
	@echo "  btrfs_integration  - Btrfs 통합 모듈"
	@echo "  anomaly_detector  - 이상 행위 감지"

# 의존성
emergency_response.o: ../../include/network_security.h ../../include/security_tools.h
btrfs_integration.o: ../../include/network_security.h
anomaly_detector.o: ../../include/network_security.h ../../include/security_tools.h
