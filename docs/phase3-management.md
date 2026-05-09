# Phase 3: 패키지 관리 및 안정성 전략

## 목표
Arch의 속도는 유지하되, 일반 사용자도 신뢰할 수 있는 **안정 채널**을 제공한다.

## 1) 패키지 관리 전략
- 기본 패키지 매니저는 `pacman` 유지.
- GUI 패키지 매니저로 `pamac-gtk` 기본 탑재.
- AUR Helper는 `yay`를 기본 제공(고급 사용자용).

### 기본 정책
1. 핵심 시스템 패키지: Stable 채널에서만 자동 업데이트
2. 일반 앱: Stable/Testing 선택 가능
3. AUR 패키지: 사용자 명시 동의 후 설치

## 2) 자체 저장소(Repo) 운영
`unifiedarch` 자체 저장소를 다음과 같이 운영:

- `unified-core` : 부팅/설치/핵심 도구
- `unified-extra` : GUI 앱/유틸리티
- `unified-testing` : 사전 검증 패키지

`config/repos/pacman-unified.conf` 예시를 배포하고 ISO에서 기본 적용한다.

## 3) 안정성 강화 프로세스
Manjaro 스타일 지연 배포 모델을 채택:

- Upstream Arch 반영 후 **7~14일 지연**
- 자동 테스트 통과 시 Stable 승격
- 실패 시 롤백 및 핫픽스

### QA 게이트
- 부팅 테스트(QEMU)
- 네트워크/그래픽/오디오 기본 동작 테스트
- 설치기(Calamares) 시나리오 테스트
- 패키지 충돌/의존성 검사

## 4) 릴리스 정책
- 월 1회 정기 릴리스 (ISO)
- 주 1회 Stable 저장소 스냅샷
- 긴급 보안 업데이트는 예외적으로 즉시 배포
