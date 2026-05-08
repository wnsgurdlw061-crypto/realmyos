#!/bin/bash
# UnifiedArch OS 통합 설치 스크립트
set -euo pipefail

VARIANT="${1:-standard}"
VARIANT_DIR="/run/archiso/variants/$VARIANT"

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }

log_info "UnifiedArch OS 설치 시작 - 변형 버전: $VARIANT"

# 변형 버전 확인
if [[ ! -d "$VARIANT_DIR" ]]; then
    log_error "변형 버전을 찾을 수 없음: $VARIANT"
    exit 1
fi

# 변형 버전별 설치 스크립트 실행
if [[ -f "$VARIANT_DIR/install-variant.sh" ]]; then
    cd "$VARIANT_DIR"
    bash install-variant.sh
    log_success "$VARIANT 변형 버전 설치 완료"
else
    log_error "설치 스크립트를 찾을 수 없음: $VARIANT_DIR/install-variant.sh"
    exit 1
fi
