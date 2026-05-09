# Phase 4: 배포 전략 및 차별화 컨셉

## 단일 핵심 컨셉: 로컬 LLM 최적화 OS

> “패키지 많이 넣은 Arch”가 아니라, **설치 직후 AI가 바로 도는 OS**에 집중한다.

## 설치 직후 경험(핵심)
- 사용자가 CUDA 버전 맞추기/드라이버 충돌 해결/PyTorch 재설치를 직접 하지 않도록 설계
- 목표 UX: **설치 → 재부팅 → 테스트 버튼 클릭 → GPU 동작 확인**

## AI 전용 런타임 통합 도구
전용 CLI `ai` 제공:
- `ai run llama3`
- `ai bench`
- `ai env switch cuda12`

이 CLI가 배포판 정체성을 만든다.

## 설치기 GPU 자동 감지 정책
- NVIDIA 감지 시: CUDA12 런타임 프로필 적용
- AMD 감지 시: ROCm 런타임 프로필 적용
- iGPU/기타: CPU 최적화 프로필 적용

프로필 결과는 `/etc/unifiedarch/ai-runtime.env`에 기록한다.

## 첫 부팅(Welcome) 액션
환영 화면에서 버튼 하나로 실행:
1. 로컬 LLM 실행해보기
2. Stable Diffusion 테스트
3. GPU 벤치마크 실행

## 릴리스/배포 체크리스트
- [x] 자동 ISO 빌드
- [x] GUI 설치기
- [x] 자체 패키지 저장소
- [x] 단일 차별화 컨셉
- [x] 정기 릴리스
