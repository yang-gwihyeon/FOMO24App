# ADR-0010 원격 개발·배포 파이프라인: Discord → PR → TestFlight → 심사 준비

## 맥락
1인 개발자가 맥북을 집에 두고 폰으로 요청해 기능 수정부터 심사 제출 직전까지 끝내고 싶다.
2026-09-19부터 Discord 채널로 Claude Code 세션을 원격 조작해 PR·머지·TestFlight(로컬 폴백)까지 실제로 돌렸고,
10-18에 릴리즈 CI 서명 문제가 풀려 태그 → TestFlight 자동 업로드가 복구됐다. 남은 빈칸은
(1) 태그 없이 테스트 빌드를 올리는 방법, (2) Claude가 "직접 돌려본" 증거, (3) 심사 준비(버전·빌드·노트·스크린샷) 자동화, (4) 상태 조회.

## 선택지
| | 장점 | 단점 |
|---|---|---|
| (a) fastlane (gym·pilot·deliver·snapshot) | 성숙, 스크린샷·메타데이터 전부 지원 | Ruby·번들러 의존, match 인증서 관리, ADR-0004에서 이미 배제한 비용 |
| (b) GitHub Actions 마켓플레이스 액션 조합 | 설정만으로 | 심사 준비(버전·노트·스크린샷)는 액션이 거의 없고, 로컬 폴백 불가 |
| **(c) `xcodebuild` + ASC REST API 직접 호출(Python, cryptography만) + Make 타깃** | 의존성 0, 전 단계가 레포 안 스크립트, 로컬/CI 동일 | API 스키마를 직접 다룸 (약 300줄), 스크린샷 프레임 꾸미기 같은 부가 기능 없음 |
| 테스트 증거 (d) 수동 시뮬레이터 스크린샷 | 즉시 | 재현 불가, 판정 없음 |
| **테스트 증거 (e) XCUITest 스모크 + 첨부 스크린샷 추출** | 판정(assert) + 증거(PNG), CI에도 올릴 수 있음 | UI 테스트 유지비, 실행 3~5분 |

## 결정
(c) + (e). 판단 기준은 **의존성 0 유지(ADR-0004 연장)** 와 **로컬·CI 같은 명령**.
- `release.yml`에 `workflow_dispatch(version)`: 테스트 빌드는 태그 없이, 빌드 번호는 run_number.
- `scripts/ship.sh`(사전 검사 후 트리거) · `scripts/status.sh` · `scripts/asc/asc.py`(auth/status/builds/wait-build/prepare/metadata/screenshots/submit) · `scripts/smoke.sh` + `UITests/SmokeTests.swift`.
- 사람 확인 게이트 4곳: 머지 · 태그 · 스크린샷/설명 교체 · 심사 제출. 심사 제출은 스크립트가 있어도 자동 실행하지 않는다.
- ASC 키는 `~/.appstoreconnect/private_keys/`(xcodebuild 기본 경로) + 루트 `.env`(gitignored). CI는 별도 시크릿.

## 결과
- 2026-10-18: 도구 6종 도입. 스모크 테스트 1건(4탭 순회·KRW 전환·스크린샷 5장).
- 첫 전 구간 실행 결과는 `docs/REMOTE_PIPELINE.md` 하단에 기록 예정 (요청 → 제출까지 소요 시간).

## 재검토 조건
- 스크린샷 프레임/다국어 10개 이상 등 메타데이터 작업이 커지면 fastlane deliver 부분 도입(ADR-0004 조건 동일).
- 스모크 테스트가 flaky해져 주 1회 이상 거짓 실패하면 네트워크 모킹(런치 인자로 MockPriceService) 도입.
