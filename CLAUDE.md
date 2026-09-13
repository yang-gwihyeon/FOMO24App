# FOMO24 — Claude Code 작업 지침

iOS 17+ · Swift 6.0 (strict concurrency = complete) · SwiftUI · Tuist 4 · Swift Testing.
한국어로 소통하고, 코드 주석도 기존 파일처럼 한국어로 쓴다.

## 무엇을 만드는 앱인가
주식·코인 선물 시세를 4개 거래소(Hyperliquid·Binance·Bitget·Bybit)에서 모아 보여주고,
"샀다 치고" 기록(FOMO)의 가상 수익률·알림, 개장 시간 시계, 투자 캘린더, 다이나믹 아일랜드 실시간 추적,
홈 위젯, 시간별 AI 브리핑 푸시를 제공한다. 거래 중개는 하지 않는다.

## 모듈 경계 (위반 = 블로커)
```
FOMOCore   순수 도메인 (모델·카탈로그·시장시간·포매터). 시스템 프레임워크만 import.
   ▲
MarketKit  거래소 시세 서비스 (URLSession). PriceService / FXProvider 프로토콜 + 구현.
   ▲
FOMO24     앱 (Views · ViewModels · Services=Firebase·알림·LiveActivity)
FOMO24Widgets  위젯·라이브액티비티 → FOMOCore 만 의존
```
- 역방향 import 금지. FOMOCore에 Firebase·서드파티 금지.
- 네트워크 코드는 MarketKit(시세) 또는 `Sources/Services`(Firebase)에만.
- 두 모듈에 걸치는 기능은 프로토콜을 아래 모듈에, 구현을 위 모듈에.

## 자주 쓰는 명령 (`make help` 참고)
```bash
make generate   # tuist generate --no-open  (xcodeproj는 git에 없음, 항상 재생성)
make test       # 모듈 유닛테스트 (FOMOCore + MarketKit) — CI와 같은 명령
make build      # 앱 시뮬레이터 빌드 (서명 없음)
make lint       # swiftlint (CODE_REVIEW.md §4 규칙 코드화)
make format     # swiftformat
make ci         # lint + test + build
```
- 로컬에 `GoogleService-Info.plist`가 없으면 `make generate`가 CI용 더미를 복사한다. 실제 키는 절대 커밋하지 않는다.
- CI 빨간불은 반드시 로컬에서 같은 `make` 타깃으로 재현한 뒤 고친다.

## 프로젝트·빌드 규칙
- 타깃·의존성·스킴 변경은 `Project.swift`에서만. 생성된 `.xcodeproj`/`.xcworkspace`는 수정 금지.
- 새 외부 패키지는 PR 본문에 근거(바이너리 크기·유지보수 비용) 필수.
- 버전은 릴리즈 CI가 태그(`v1.2`)에서 주입. 로컬 기본값은 `Project.swift` 상단.

## 코드 규칙 (전문은 CODE_REVIEW.md)
- 앱 코드에서 `!` 강제 언래핑·`try!` 금지 (컴파일타임 보장 리터럴 URL·테스트는 예외).
- `nonisolated(unsafe)`는 SDK 타입이 non-Sendable이지만 스레드 세이프임이 문서로 확인될 때만, 주석과 함께.
- 전역 가변 상태는 `@MainActor` 격리. public 값 타입은 `Sendable` 명시.
- 원격 데이터 파싱은 실패 허용(`compactMap` + 기본값). 시스템 API 실패는 조용히 무시하되 주석으로 의도 명시.
- 뷰 바디에서 포매터·캘린더 생성 금지 → `Fmt`, `MarketSession.calendar(for:)` 캐시 사용.
- 주석은 "코드가 말할 수 없는 제약"만 (왜 캐시하는지, 왜 무시하는지).

## 테스트 규칙
- FOMOCore·MarketKit의 계산·파싱·판정 로직을 바꾸면 Swift Testing 테스트를 함께 추가한다.
- 네트워크·현재 시각에 의존하지 않는다: 날짜는 고정 값 주입, 시세는 `MockPriceService`.
- 테스트 이름은 한국어 서술형: `미국_프리마켓은_preMarket()`. 실패 메시지가 곧 명세.

## 작업 방식 (중요)
- **성능 관련 변경은 측정 전에 하지 않는다.** 기준선 → 가설 → 선택지 → 결정 → 재측정. 기록은 `docs/perf/`.
- 모든 PR 본문은 `.github/pull_request_template.md`의 6칸(관찰·가설·선택지·결정·측정·배운 것)을 채운다.
  선택지는 최소 2개, 트레이드오프 명시. 사용자가 면접에서 스스로 설명할 수 있어야 한다.
- 아키텍처 수준 결정은 `docs/adr/`에 ADR로 남긴다.
- 커밋 메시지: Conventional Commits 한국어 (`feat:`, `fix:`, `ci:`, `chore:`, `perf:`, `docs:`).
- 커밋 전 `git diff --cached`에서 API 키·토큰 패턴 확인 (`scripts/check-secrets.sh`).

## 하지 말 것
- `GoogleService-Info.plist`, `AuthKey_*.p8`, `.env` 커밋.
- 공개 저장소이므로 셀프 호스티드 러너 추가.
- main에 직접 푸시(브랜치 보호 적용 후). PR로만.
