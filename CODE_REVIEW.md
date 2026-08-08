# FOMO24 코드리뷰 규칙

모든 PR/커밋은 아래 체크리스트로 리뷰한다. 위반은 심각도(P1 블로커 / P2 수정 권장 / P3 제안)를 붙여 보고한다.

## 1. 아키텍처 경계 (P1)

- **의존성 방향은 단방향**: 앱 → MarketKit → FOMOCore, 위젯 → FOMOCore. 역방향 import는 블로커.
- **FOMOCore에 외부 SDK 금지**: Foundation/SwiftData/ActivityKit 등 시스템 프레임워크만 허용. Firebase·서드파티가 들어오면 블로커.
- **네트워크 코드는 MarketKit(시세) 또는 앱 Services(Firebase)에만**: 뷰·모델에서 URLSession 직접 사용 금지.
- 새 기능이 두 모듈에 걸치면 프로토콜을 FOMOCore(또는 MarketKit)에 두고 구현을 위로 올린다.

## 2. Swift 6 / 동시성 (P1)

- `nonisolated(unsafe)`는 **SDK 타입이 non-Sendable이지만 API가 스레드 세이프함이 문서로 확인될 때만**, 반드시 주석과 함께. 자체 타입에 쓰면 블로커.
- 전역 가변 상태(`static var`)는 `@MainActor` 격리 또는 락 필수.
- public 값 타입은 `Sendable` 명시 (public은 자동 추론 안 됨).
- 외부 SDK 델리게이트는 `nonisolated`로 받고 `Task { @MainActor in }`으로 홉.
- `Task.detached`는 격리 회피 목적일 때만 — 우선순위 상속이 필요한 UI 후속 작업엔 `Task {}`.

## 3. 테스트 (P2)

- **순수 로직 추가/변경 시 테스트 동반**: FOMOCore·MarketKit의 계산/파싱/판정 로직은 Swift Testing 테스트 필수.
- 테스트는 네트워크·시간에 의존하지 않는다: 날짜는 고정 값으로 주입, 시세는 `MockPriceService`.
- 테스트 이름은 한국어 서술형 (`미등록_티커는_티커를_그대로_반환`) — 실패 메시지가 곧 명세가 되도록.

## 4. 크래시·안정성 (P1)

- 강제 언래핑(`!`)·`try!`는 앱 코드에서 금지 (테스트/컴파일타임 보장 리터럴 URL은 예외).
- 원격 데이터(Firestore·거래소 API) 파싱은 항상 실패 허용: `compactMap` + 기본값 유지 패턴 유지.
- LiveActivity·알림 등 시스템 API 실패는 조용히 무시하되 주석으로 의도 명시.

## 5. 프로젝트·빌드 (P2)

- 타깃/의존성 변경은 `Project.swift`에서만 — 생성된 xcodeproj 직접 수정 금지 (git에 없음).
- 새 외부 패키지 추가는 리뷰에서 근거 요구 (바이너리 크기·유지보수 비용).
- CI가 빨간불이면 머지 금지. CI 수정은 로컬에서 동일 명령으로 재현 후 커밋.

## 6. 보안 (P1)

- `GoogleService-Info.plist` 등 실제 키 파일 커밋 금지 — gitignore 확인. 더미는 `CI/`에만.
- 커밋 전 `git diff --cached`에서 API 키·토큰 패턴 확인.

## 7. 스타일 (P3)

- 기존 파일의 주석 밀도·네이밍·한국어 주석 스타일을 따른다.
- 주석은 "코드가 말할 수 없는 제약"만: 왜 CPU 모드인지, 왜 캐시하는지, 왜 무시하는지.
- 뷰 바디에서 포매터·캘린더 생성 금지 — `Fmt`/`MarketSession.calendar(for:)` 캐시 사용.
