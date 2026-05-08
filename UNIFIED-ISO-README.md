# UnifiedArch OS 통합 ISO 시스템

## 개요

UnifiedArch OS 통합 ISO 시스템은 4가지 변형 버전을 모두 포함하는 단일 ISO 이미지를 생성합니다. 부팅 시 원하는 변형 버전을 선택하여 설치할 수 있습니다.

## 포함된 변형 버전

### 1. **Standard** (2GB) - 모든 기능 포함
- GNOME, KDE, XFCE, MATE, Cinnamon 데스크톱 환경
- 개발 도구, 멀티미디어, 오피스 애플리케이션
- 가상화, 게이밍 지원
- 완전한 기능을 제공하는 표준 버전

### 2. **Minimal** (800MB) - 극단적 경량화
- i3 창 관리자 기반의 최소한의 환경
- 필수 시스템 도구만 포함
- 빠른 부팅과 낮은 메모리 사용량
- 서버나 최소한의 데스크톱 환경에 적합

### 3. **Enterprise** (3GB) - 서버 등급
- LTS 커널 기반의 안정적인 서버 환경
- 데이터베이스, 컨테이너, 모니터링 도구
- 보안 및 하드웨어 모니터링
- 기업 환경에 최적화된 서버 등급

### 4. **Gaming** (4GB) - 게이밍 최적화
- Zen 커널 기반의 게이밍 최적화
- 최신 그래픽 드라이버와 Vulkan 지원
- Steam, Lutris, Wine/Proton
- 게이밍 퍼포먼스 최적화 도구

## 사용 방법

### 빌드 시스템 설치 요구사항

```bash
# Arch Linux 기반 시스템
sudo pacman -S archiso xorriso squashfs-tools

# 또는 필수 도구만 설치
sudo pacman -S base-devel git xorriso squashfs-tools
```

### 통합 ISO 빌드

```bash
# 전체 빌드 (권장)
./build-unified-iso.sh

# 단계별 빌드
./build-unified-iso.sh profiles     # 변형 버전 프로필 생성
./build-unified-iso.sh bootmenu    # 부트 메뉴 생성
./build-unified-iso.sh iso         # ISO 이미지 생성
```

### 빌드 옵션

```bash
./build-unified-iso.sh [옵션]

옵션:
  all          - 전체 통합 빌드 (기본)
  profiles     - 변형 버전 프로필만 생성
  bootmenu     - 부트 메뉴만 생성
  profile      - 통합 프로필만 생성
  integrate    - 데이터 통합만 수행
  iso          - ISO 이미지만 생성
  checksum     - 체크섬만 생성
  clean        - 빌드 파일 정리
  help         - 도움말 표시
```

## 부트 메뉴 시스템

통합 ISO는 다음과 같은 부트 메뉴를 제공합니다:

### 메인 메뉴
1. **UnifiedArch OS 변형 버전 선택** - 상세 선택 메뉴로 이동
2. **Standard (2GB)** - 바로 Standard 버전 부팅
3. **Minimal (800MB)** - 바로 Minimal 버전 부팅
4. **Enterprise (3GB)** - 바로 Enterprise 버전 부팅
5. **Gaming (4GB)** - 바로 Gaming 버전 부팅
6. **Memory Test** - 메모리 테스트 실행
7. **Reboot System** - 시스템 재부팅
8. **Power Off** - 시스템 전원 끄기

### 상세 선택 메뉴
각 변형 버전의 상세 설명과 함께 선택 가능

## 파일 구조

```
/home/me/문서/os/
├── build-unified-iso.sh          # 통합 ISO 빌드 스크립트
├── variants/                      # 변형 버전 설정
│   ├── standard/
│   │   └── packages.x86_64      # Standard 패키지 목록
│   ├── minimal/
│   │   └── packages.x86_64      # Minimal 패키지 목록
│   ├── enterprise/
│   │   └── packages.x86_64      # Enterprise 패키지 목록
│   └── gaming/
│       └── packages.x86_64      # Gaming 패키지 목록
├── build/
│   └── unified-iso/              # 통합 빌드 작업 디렉토리
└── iso/                          # 최종 ISO 출력 디렉토리
```

## 설치 과정

1. **ISO 부팅**: 통합 ISO로 시스템 부팅
2. **변형 버전 선택**: 부트 메뉴에서 원하는 변형 버전 선택
3. **Live 환경**: 선택된 변형 버전의 Live 환경 시작
4. **설치 실행**: 통합 설치 스크립트로 설치 진행
5. **변형 버전별 설정**: 선택된 변형 버전에 맞는 설정 자동 적용

## 기술적 특징

### 부트 로더 지원
- BIOS (Legacy) 부팅 지원
- UEFI 부팅 지원
- Secure Boot 호환

### 커널 옵션
- **Standard**: 기본 Linux 커널
- **Minimal**: 기본 Linux 커널 (최소화)
- **Enterprise**: Linux LTS 커널 (안정성)
- **Gaming**: Linux Zen 커널 (성능 최적화)

### 파일 시스템
- SquashFS 압축 파일 시스템 사용
- OverlayFS를 통한 Live 환경 지원
- 변형 버전별 분리된 패키지 관리

## 트러블슈팅

### 빌드 실패 시
```bash
# 빌드 환경 정리
./build-unified-iso.sh clean

# 필수 도구 재설치
sudo pacman -S archiso xorriso squashfs-tools

# 다시 빌드
./build-unified-iso.sh
```

### 부팅 문제 시
1. BIOS/UEFI 설정 확인 (Secure Boot 비활성화)
2. USB 미디어 다시 생성 (dd 명령어 사용 권장)
3. 하드웨어 호환성 확인

### 설치 문제 시
1. 네트워크 연결 확인
2. 저장 공간 확보 (최소 20GB 권장)
3. 변형 버전별 요구사양 확인

## 시스템 요구사양

### 최소 요구사양
- **CPU**: x86_64 아키텍처
- **메모리**: 2GB RAM (Minimal 1GB)
- **저장공간**: 20GB (각 변형 버전별로 상이)
- **부팅**: USB 또는 DVD 드라이브

### 권장 사양
- **CPU**: 멀티코어 프로세서
- **메모리**: 8GB+ RAM
- **저장공간**: 50GB+ SSD
- **그래픽**: 최신 그래픽 카드 (Gaming 버전)

## 라이선스

GPL v3.0 라이선스에 따라 배포됩니다.

## 기여

기여는 환영합니다. 자세한 내용은 CONTRIBUTING.md를 참조하세요.

---

**UnifiedArch OS 통합 ISO 시스템** - 하나의 ISO로 모든 변형 버전을!
