# UnifiedArch 실행 로드맵 (요청 반영)

## 🏗 1단계: 기본 완성도 확보

### 1. ISO 자동 빌드 시스템 (Archiso)
- Arch 공식 도구 `archiso` 기반으로 ISO 생성
- 커스텀 패키지 리스트: `build/iso/profile/packages.x86_64`
- 자동 빌드 스크립트: `scripts/build-iso-archiso.sh`
- GitHub Actions 자동 빌드: `.github/workflows/build-iso.yml`

### 2. 설치 프로그램 탑재
- GUI 설치기 `Calamares` 채택
- 설치/첫 부팅에서 GPU 자동 감지 후 런타임 프로필 적용

## ⚙️ 2단계: Arch와의 차별화

### 3. 패키지 관리 전략
- 기본 `pacman`
- GUI 패키지 매니저 `pamac-gtk`
- 자체 저장소 `unified-core/unified-extra/unified-testing`

### 4. 안정성 강화
- Stable/Testing 브랜치 분리
- 1~2주 지연 배포
- QA 통과 후 Stable 반영

### 5. 핵심 차별화 기능 (단일 선택)
- **로컬 LLM 최적화 OS**로 집중
- 전용 CLI: `ai run`, `ai bench`, `ai env switch`

## 🎨 3단계: 사용자 경험

### 6. 기본 데스크탑 완성도
- KDE Plasma(기본안)
- 테마/기본 앱/시스템 설정 통일

### 7. OOBE
- 첫 부팅 가이드
- GPU 동작 테스트 버튼
- Stable Diffusion 테스트 버튼
- 로컬 LLM 실행 버튼
- 업데이트 확인

## 🌍 4단계 체크
| 항목 | 필요 여부 |
|---|---|
| 자동 ISO 빌드 | ✅ |
| GUI 설치기 | ✅ |
| 자체 패키지 저장소 | ✅ |
| 차별화 컨셉 | ✅ |
| 정기 릴리스 | ✅ |
