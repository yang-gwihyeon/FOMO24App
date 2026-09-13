# FOMO24 AI 네이티브 개발 워크플로

```mermaid
flowchart LR
  I[이슈 작성<br/>문제·완료기준] --> A{누가 구현?}
  A -->|@claude 멘션| C[Claude Code Action<br/>브랜치 + PR 초안]
  A -->|로컬| L[Claude Code CLI<br/>CLAUDE.md 규칙 적용]
  C --> P[PR: 6칸 카드]
  L --> P
  P --> G1[lint · format<br/>ubuntu 수초]
  P --> G2[테스트 · 빌드<br/>macOS]
  P --> R[AI 리뷰<br/>CODE_REVIEW.md 기준 P1~P3]
  G1 & G2 & R --> H[사람 최종 판단<br/>측정 수치 확인]
  H --> M[머지 main]
  M --> T[태그 v1.x] --> F[TestFlight 자동 업로드]
```

## 각 단계에서 사람이 하는 것 / AI가 하는 것
| 단계 | 사람 | AI |
|---|---|---|
| 이슈 | 문제·완료 기준·측정 지표 정의 | — |
| 구현 | 선택지 중 결정, 기준 제시 | 선택지 나열, 초안 코드, 테스트 초안 |
| PR 카드 | 관찰·결정·측정 작성 | 가설·선택지 표 초안 |
| 게이트 | 린트 규칙 정의(`.swiftlint.yml`) | 규칙 통과하도록 수정 |
| 리뷰 | `CODE_REVIEW.md` 작성·갱신 | 문서 기준으로 코멘트 |
| 머지 | 측정 수치 확인 후 승인 | — |

## 강제 장치 (없으면 흐름이 무너지는 것)
1. `CLAUDE.md` — AI 컨텍스트 = 온보딩 문서
2. `.github/pull_request_template.md` — 6칸 카드
3. `.swiftlint.yml` — 리뷰 규칙의 기계화
4. `.claude/settings.json` — 편집 후 포맷 훅, 커밋 전 시크릿 검사 훅
5. `docs/perf/` — 측정 없는 성능 변경 금지
6. `docs/adr/` — 아키텍처 결정 기록

## 상태 (2026-09-12)
- [x] 1, 2, 3, 4, 5(템플릿), 6(ADR 6건)
- [x] main 브랜치 보호 (2026-09-13): PR 필수, 필수 체크 = SwiftFormat 검사 · 모듈 테스트 + 앱 빌드, 관리자 포함 강제, force push·삭제 금지
- [x] CI lint/format 잡 분리 (2026-09-13): ubuntu 컨테이너/docker run, 각 15초 내. SwiftLint는 기준선 error 5 해소 전까지 continue-on-error
- [x] Dependabot 첫 PR 2건 (checkout v7, cache v6) — 무료 티어에서 자동 생성·CI 통과·머지
- [ ] `claude.yml` AI 리뷰 워크플로 — Anthropic API 키 또는 Claude 구독 OAuth 토큰을 Secrets에 넣어야 함 (사용자 결정 필요)
- [ ] B0 기준선 측정 (실기기 + Instruments, 사용자와 함께)
- [ ] 첫 카드형 PR: 앱 코드 강제 언래핑 5곳 제거 → SwiftLint 잡을 블로킹으로 전환
