# FOMO24 · AI 최적화 개발환경 + 면접 대비 계획

작성일: 2026-09-12 · 원칙: **GitHub 무료 티어만**, 모든 작업은 **내가 논리적으로 설명할 수 있는 형태**로 남긴다.

---

## Part 1. 운영 원칙 — "AI에게 시켰다"를 "내가 결정했다"로 바꾸는 구조

### 1.1 역할 분담 (면접에서 그대로 말하는 문장)
| 내가 하는 것 | AI가 하는 것 |
|---|---|
| 문제 발견 (측정·로그·리뷰 규칙 위반) | 원인 후보 나열 |
| 판단 기준 정의 (수치 목표·트레이드오프 축) | 선택지별 구현 초안 |
| 선택지 중 결정 + 근거 기록 | 결정된 방식으로 코드 작성 |
| 측정으로 검증 (전/후 수치) | 테스트 초안·리뷰 코멘트 |
| 최종 머지 판단 | — |

> "AI는 선택지와 초안을 빠르게 만들어 주는 도구고, 무엇이 문제인지·어떤 기준으로 고를지·결과가 맞는지는 제가 정의하고 측정했습니다."

### 1.2 작업 카드 템플릿 (모든 PR·ADR에 강제)
```
## 관찰      어떻게 문제를 알았나 (도구·수치·규칙 위반)
## 가설      원인이 무엇이라고 생각했나
## 선택지    최소 2개 + 각 트레이드오프
## 결정      무엇을 골랐고 왜 (기준 명시)
## 측정      전 → 후 수치, 사용 도구
## 배운 것   다음에 다르게 할 점
```
이 6칸이 채워지지 않은 PR은 머지하지 않는다. PR 템플릿(`.github/pull_request_template.md`)에 이 형식을 넣어 자연스럽게 기록이 쌓이게 한다.

### 1.3 나쁜 답 vs 좋은 답 (예시: 정렬 성능)
- ✗ "리스트가 느려서 클로드한테 최적화해 달라고 했어요."
- ✓ "Instruments Time Profiler로 5초 폴링마다 `displayedTickers` 가 computed property라 뷰가 그려질 때마다 O(n log n) 정렬이 다시 돌고 있는 걸 봤습니다. 선택지는 (a) 데이터 변경 시점에만 정렬해 캐시, (b) 뷰에서 `sorted`를 제거하고 저장 시 정렬, (c) 그대로 두기. 종목 수가 100개 미만이라 절대 시간은 작았지만 body 호출당 반복되는 구조가 문제라 (a)를 택했고, body당 정렬 횟수가 N→1, 스크롤 중 CPU가 X%→Y%로 줄었습니다. 구현 초안은 AI가 썼고, 기준과 측정은 제가 했습니다."

---

## Part 2. 현재 진단 (2026-09-12)

### 잘 되어 있는 것
Tuist 단일 소스 · 3모듈 단방향 의존(FOMOCore ← MarketKit ← 앱/위젯) · Swift 6 strict concurrency · Swift Testing 27개 · CI + 태그→TestFlight 자동 배포 · `CODE_REVIEW.md` 리뷰 규칙 · 시크릿 분리.

### 막고 있는 것 (P1)
- GitHub 계정 **`yang-gwihyeon`(저장소 소유)** 이 빌링 사유로 잠김 → 8/9 이후 모든 Actions 런 3초 만에 실패.
  `The job was not started because your account is locked due to a billing issue.`
- 크롬에 로그인된 `yanggwihyeon` 은 다른 계정(저장소 0개)이라 이전엔 문제를 못 찾았음.

### 비어 있는 것
`CLAUDE.md` · `README.md` · SwiftLint/SwiftFormat · PR 워크플로(PR 0건, main 직접 푸시) · Dependabot · 프로젝트 `.claude/` 설정 · **성능 측정 기준선(baseline) 전무**.

### 코드에서 이미 보이는 성능 후보 (Track B 의 출발점)
| # | 위치 | 관찰 | 왜 문제 후보인가 |
|---|---|---|---|
| P1 | `PriceStore.displayedTickers` | computed property 안에서 매번 `sorted` | 뷰 body마다 재정렬. 5초 폴링 × 스크롤 리렌더와 곱해짐 |
| P2 | `PriceStore.refresh()` | 5초마다 `quotes` 딕셔너리 전체 교체 | `@Observable` 이 전체 변경으로 인식 → 모든 행 리렌더 가능성. 메모리 할당 반복 |
| P3 | `fetchAllSources()` | 5초마다 4개 거래소 병렬 요청, 매번 `makeService()` 새 인스턴스 | 분당 48회 요청. 배터리·데이터. 디코더/서비스 재생성 |
| P4 | `LiveActivityManager.watchState` | 액티비티마다 `Task { for await ... }` 무한 대기, `self` 강참조 | 액티비티 종료까지 Task 생존. 재시작 반복 시 누적 여부 확인 필요 |
| P5 | `UpdateGate` Firestore `addSnapshotListener` | 해제 경로 확인 필요 | 리스너 누수는 메모리+네트워크 둘 다 |
| P6 | `PriceWidget` 타임라인 15분 | 위젯 익스텐션 메모리 한도 30MB | 폰트·이미지 로딩 방식에 따라 한도 초과 크래시 |
| P7 | 앱 기동 | Firebase configure + 첫 폴링 | cold launch 첫 프레임 시간 미측정 |

이 표는 "가설" 단계다. **측정 전에는 고치지 않는다.** 측정해서 문제가 아니면 "측정했더니 문제 아니었다"도 면접 답이 된다.

---

## Part 3. 트랙별 계획

### Track A — 인프라·자동화 (Phase 0~2)

#### A0. 계정 잠금 해제 + CI 복구 (오늘, 사용자 손 필요)
1. 크롬에서 `yanggwihyeon` 로그아웃 → `yang-gwihyeon` 로그인
2. https://github.com/settings/billing 잠금 배너 확인 → 미납 결제 또는 Support 티켓
3. `gh run rerun 33384310518` 로 재실행, 녹색 확인
- 면접 문장: "공개 저장소라 Actions는 무료·무제한인데도 계정 잠금은 별개라는 걸 CI 3초 실패 로그로 확인했다."

#### A1. 저장소를 AI가 읽을 수 있게 (1일)
| 산출물 | 내용 | 설명 포인트 |
|---|---|---|
| `CLAUDE.md` | 모듈 경계, `make` 명령, 리뷰 규칙 요약, 금지 패턴 | "AI 컨텍스트를 문서화하면 사람 온보딩 문서와 같아진다" |
| `Makefile` | `generate / test / build / lint / format / perf` — CI와 로컬 동일 명령 | "CI 빨간불을 로컬에서 같은 명령으로 재현" |
| `.swiftlint.yml` | `force_unwrapping`·`force_try` = error, `CODE_REVIEW.md` §4 코드화 | "사람 리뷰 규칙을 기계가 강제" |
| `.swiftformat` | 기존 스타일 기준 최소 규칙 | — |
| `.claude/settings.json` | `.swift` 편집 후 swiftformat 훅, 커밋 전 시크릿 패턴 검사 훅 | "AI가 규칙을 어기지 못하게 훅으로 가드" |
| `README.md` | 소개·앱스토어 링크·mermaid 아키텍처·CI 배지 | 포트폴리오 첫 화면 |

#### A2. PR 워크플로 + AI 리뷰 (1~2일)
| 작업 | 설명 포인트 |
|---|---|
| main 보호: PR 필수, CI 필수 | "1인 개발에서도 PR 이력이 곧 결정 기록" |
| `ci.yml` 분리: lint는 `ubuntu-latest`(수 초), 테스트·빌드만 macOS | "무료 분량과 피드백 속도 둘 다 고려" |
| PR 템플릿 = 1.2 작업 카드 | 기록이 강제로 쌓임 |
| `dependabot.yml` (actions + swift) | 공급망 관리 |
| `claude.yml`: PR 자동 리뷰(`CODE_REVIEW.md` 기준 P1~P3), 이슈 `@claude` → 구현 PR | "리뷰 기준은 내가 쓴 문서, AI는 그걸 적용" |

### Track B — 성능 (메모리·CPU·네트워크·기동·위젯) ★ 면접 핵심

각 항목은 **① 기준선 측정 → ② 가설 → ③ 선택지 → ④ 결정 → ⑤ 재측정** 순서. 결과는 `docs/perf/` 에 `YYYY-MM-DD-<주제>.md` 로 작업 카드 형식 저장, 스크린샷 포함.

#### B0. 기준선 만들기 (반나절) — 모든 성능 작업의 전제
| 지표 | 도구 | 방법 |
|---|---|---|
| 메모리 (앱) | Xcode Debug Navigator + Instruments **Allocations** | 기동 → 30분 폴링 방치 → 그래프 기울기 기록 |
| 누수 | Instruments **Leaks**, **Memory Graph Debugger** | LiveActivity 시작/종료 10회 반복 후 그래프 |
| CPU/렌더 | Instruments **Time Profiler**, **SwiftUI** 템플릿(body 호출 수) | 대시보드에서 60초 스크롤 |
| 네트워크 | Instruments **Network**, Charles/Proxyman | 1분간 요청 수·바이트 |
| 배터리 | Instruments **Energy Log**, 설정→배터리 | 30분 포그라운드 |
| 기동 | Xcode Organizer **Launch Time**, `os_signpost` | cold launch 10회 평균 |
| 위젯 메모리 | 위젯 익스텐션 attach → Debug Navigator | 30MB 한도 대비 |
| 빌드 시간 | `xcodebuild -showBuildTimingSummary`, CI 런 시간 | 클린 빌드 / 증분 빌드 |
- 면접 문장: "고치기 전에 기준선을 먼저 만들었다. 숫자가 없으면 개선도 없다."

#### B1. 메모리 (1~2일)
| 후보 | 가설 | 선택지 | 측정 |
|---|---|---|---|
| P4 LiveActivity Task | 액티비티 반복 시 Task·클로저 누적 | (a) Task 핸들 보관 후 종료 시 cancel (b) `[weak self]` + guard (c) 상태 감시를 단일 스트림으로 통합 | 10회 반복 후 Memory Graph의 `Task`·`LiveActivityManager` 인스턴스 수 |
| P2 quotes 전체 교체 | 5초마다 딕셔너리 재할당 | (a) 변경된 티커만 갱신 (b) 그대로 (할당은 작음) | Allocations의 5초 주기 스파이크 크기 |
| P5 Firestore 리스너 | 화면 이탈 후 리스너 잔존 | `ListenerRegistration.remove()` 호출 경로 확인 | 리스너 등록 수 로그 |
| P6 위젯 | 커스텀 폰트·이미지 로드가 30MB 근접 | 폰트 서브셋 / 시스템 폰트 폴백 | 위젯 프로세스 메모리 |
| 캐시 정책 | `Fmt` 포매터·`MarketSession.calendar` 캐시 무한 증가 여부 | 상한 있는 캐시 (NSCache / LRU) | 캐시 항목 수 |
- 설명 포인트: ARC와 Task 수명 · `@Observable` 변경 추적 단위 · 익스텐션 메모리 한도 · "누수가 아니라 정상 성장"을 구분하는 법 (Generations 비교).

#### B2. CPU·렌더링 (1일)
| 후보 | 선택지 | 측정 |
|---|---|---|
| P1 `displayedTickers` 매 접근 정렬 | (a) `quotes`·`sortOption`·`appLanguage` 변경 시에만 재계산해 저장 (b) 뷰에서 `.sorted` 제거 | body당 정렬 호출 수, 스크롤 CPU% |
| 행 리렌더 범위 | `@Observable` 속성 분리 / 행 뷰에 `Equatable` 값 전달 | SwiftUI Instruments body 호출 수 |
| 포매터 | 뷰 바디 내 생성 금지(이미 규칙) 준수 확인 | Time Profiler `NumberFormatter.init` 호출 |
- 설명 포인트: SwiftUI 무효화 단위 · computed vs stored 트레이드오프 · "작은 n에서 최적화가 의미 있는가"를 수치로 판단.

#### B3. 네트워크·배터리 (1~2일)
| 후보 | 선택지 | 트레이드오프 |
|---|---|---|
| P3 5초 × 4거래소 폴링 | (a) 유지 (b) 화면에 보이는 티커·선택 거래소만 요청 (c) 앱 비활성/저전력 모드 시 주기 완화 (d) 웹소켓 전환 | (d)는 복잡도·재연결 처리 부담, (b)(c)는 코드 변경 작고 효과 큼 → 먼저 (b)(c) |
| `URLSession.shared` | 전용 세션: `timeoutIntervalForRequest`, `waitsForConnectivity`, 요청 병합 | 실패 시 부분 표시 정책 유지 |
| 서비스 인스턴스 재생성 | 서비스·`JSONDecoder` 재사용 | 미미할 수 있음 → 측정으로 판단 |
- 측정: 분당 요청 수 48 → ?, 바이트/분, Energy Log 등급.
- 설명 포인트: 폴링 vs 스트리밍 결정 기준 · 저전력 모드 대응 · "일부 실패 무시" 정책이 UX에 미치는 영향.

#### B4. 앱 기동 (반나절)
- `os_signpost` 로 `didFinishLaunching → 첫 프레임 → 첫 시세 표시` 구간 측정.
- 선택지: Firebase configure 지연 / 첫 화면은 캐시된 마지막 시세로 즉시 표시(UserDefaults 또는 파일) / 폰트 사전 로드.
- 설명 포인트: 사용자가 느끼는 기동 = 첫 의미 있는 화면. 캐시 우선 표시(stale-while-revalidate) 패턴.

#### B5. 빌드·CI 시간 (반나절)
- 모듈별 빌드 시간, SPM 캐시 적중률, CI 평균 시간 기록. Tuist 캐시(`tuist cache`) 적용 여부 검토.
- 설명 포인트: "모듈화의 실제 이득을 빌드 시간으로 증명".

### Track C — 품질 신호 (Phase 3, 2~3일)
| 작업 | 설명 포인트 |
|---|---|
| 커버리지(`xccov`) → PR 코멘트 | "AI가 만든 코드일수록 테스트가 계약" |
| Periphery 데드 코드 주간 스캔 | 유지보수 근거 |
| 스냅샷 테스트(대시보드·위젯) | UI 회귀 안전망 |
| `release-drafter` 릴리즈 노트 | Conventional Commits 이미 사용 중 |
| 성능 회귀 테스트: XCTest `measure` 로 정렬·파싱 벤치 | B 트랙 결과를 지키는 장치 |

### Track D — 포트폴리오·면접 (Phase 4, 1일 + 상시)
| 산출물 | 내용 |
|---|---|
| `docs/adr/` | Tuist 채택 · 모듈 분리 · Swift 6 strict · TestFlight 자동화 · AI 리뷰 도입 · 폴링 유지/변경 결정 |
| `docs/perf/` | B 트랙 작업 카드 + Instruments 스크린샷 |
| `docs/AI_WORKFLOW.md` | 이슈 → AI 구현 → AI 리뷰 → CI → TestFlight 다이어그램 + 실제 PR 링크 |
| README 지표 | 테스트 수·커버리지·CI 시간·메모리/기동 전후 |
| 경력기술서 항목 | "1인 개발에서 AI 에이전트 + CI/CD + 성능 측정 루프 구축" — 수치와 링크 |

---

## Part 4. 예상 면접 질문 → 답변 골격

| 질문 | 골격 (관찰→기준→결정→측정) |
|---|---|
| AI를 개발에 어떻게 쓰셨나요? | 역할 분담 표(1.1). 예시 하나(P1 정렬)로 6칸 카드 그대로 말하기 |
| AI가 만든 코드는 어떻게 검증하나요? | 리뷰 규칙 문서 → SwiftLint 코드화 → 테스트 → CI → 성능 회귀 벤치. "기준은 내가 썼다" |
| 메모리 이슈를 어떻게 찾고 해결했나요? | B0 기준선 → Allocations 기울기 → Memory Graph 인스턴스 수 → 원인(Task 수명) → 수정 → 재측정 |
| 왜 5초 폴링인가요, 웹소켓은? | B3 트레이드오프. "복잡도 대비 효과가 작은 순서로 (b)(c) 먼저, 웹소켓은 측정 결과로 판단" |
| Swift 6 concurrency 도입하며 어려웠던 점? | `nonisolated(unsafe)` 정책, SDK 델리게이트 홉, 전역 상태 격리 — `CODE_REVIEW.md` §2 |
| 모듈을 왜 나눴나요? | 의존 방향·테스트 격리·빌드 시간(B5 수치) |
| 1인 개발인데 PR·리뷰가 왜 필요했나요? | "결정 기록 + AI 리뷰 게이트 + CI 강제". PR 링크 |
| 비용은 얼마나 들었나요? | GitHub 0원: 공개 저장소·러너 선택·예산 상한. 근거 설명 |
| 실패한 시도는? | "측정했더니 문제 아니었던 것"(예: P2 할당 스파이크가 무의미했다면) 그대로 말하기 |
| 다음에 할 것은? | 웹소켓 검토, 스냅샷 확대, 위젯 푸시 갱신 |

---

## Part 4.5 진행 현황 (2026-09-12)

완료 (다른 세션의 브리핑 기능 작업과 겹치지 않는 범위):
- `CLAUDE.md`, `README.md`, `Makefile`, `.swiftlint.yml`, `.swiftformat`, `scripts/check-secrets.sh`
- `.claude/settings.json` 훅 (편집 후 swiftformat, `git commit` 전 시크릿 검사)
- `.github/`: PR 템플릿(6칸 카드), 이슈 템플릿 2종, `dependabot.yml`, `CODEOWNERS`
- `docs/adr/` 6건, `docs/perf/README.md`(B0 체크리스트 + 가설 P1~P8), `docs/AI_WORKFLOW.md`
- 로컬 툴 설치: xcbeautify · swiftlint 0.65 · swiftformat 0.63
- 린트 기준선: 170 → 24 (규칙을 기존 정렬 스타일에 맞춘 뒤). 남은 error 5 = 앱 코드 강제 언래핑 5곳
  (`App.swift` DEBUG 데모 3, `MoreView:105`, `CalendarStore:102`) → 첫 번째 카드형 PR 후보

보류 (브리핑 기능 커밋 후):
- `Project.swift`·`ci.yml` 수정(lint 잡 분리), main 브랜치 보호, `claude.yml`
- ~~사용자 손 필요: `yang-gwihyeon` 계정 잠금 해제~~ → 2026-09-13 해결. 원인: 2024-06-27 Copilot 추정 $10 결제가 JCB 카드에서 거절 → 계정 잠금 2년 지속. 카드를 MasterCard로 교체하자 약 20분 내 자동 해제. CI 재실행 녹색(11m30s).
- CI 첫 녹색 런의 경고: `AppFont.swift:29-31` UIKit appearance 호출이 nonisolated 컨텍스트 (Swift 6 경고 5건) · `actions/checkout@v4`·`cache@v4` Node 20 deprecated → 카드형 PR 후보 2개 추가

## Part 5. 실행 순서와 소요
```
A0 계정 해제(오늘) → A1 문서·툴(1일) → B0 기준선(0.5일)
→ A2 PR 워크플로(1~2일) → B1 메모리(1~2일) → B2 렌더(1일) → B3 네트워크(1~2일)
→ B4 기동(0.5일) → C 품질(2~3일) → B5 빌드(0.5일) → D 포트폴리오(1일)
```
약 2주. B0 이후의 모든 성능 작업은 PR 1개 = 작업 카드 1개 = `docs/perf/` 문서 1개로 남긴다.

## Part 6. 무료 티어 규칙
- 저장소 공개 유지 → Actions(macOS 포함) 무제한 무료. 비공개 시 월 2,000분(macOS 10배 차감).
- 공개 저장소이므로 셀프 호스티드 러너 금지(포크 PR 코드 실행 위험).
- 시크릿은 Actions Secrets에만, 커밋 전 훅으로 이중 검사.
- 빌링 예산 $0 + 초과 시 중단 유지.
