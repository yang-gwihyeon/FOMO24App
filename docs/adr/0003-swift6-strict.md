# ADR-0003 Swift 6 strict concurrency = complete

## 맥락
시세 폴링(백그라운드 태스크), Firebase 델리게이트(임의 스레드), LiveActivity 갱신이 섞여 데이터 레이스 위험이 있었다.

## 선택지
| | 장점 | 단점 |
|---|---|---|
| (a) Swift 5 모드 유지 | 마이그레이션 비용 0 | 레이스를 런타임에만 발견 |
| (b) `minimal` 경고만 | 점진적 | 경고는 무시되기 쉬움 |
| (c) **`complete` + Swift 6 언어 모드** | 컴파일타임 보장 | SDK non-Sendable 타입 우회 필요 |

## 결정
(c). 우회 규칙을 `CODE_REVIEW.md` §2에 명문화: `nonisolated(unsafe)`는 SDK 타입이 스레드 세이프임이 문서로 확인될 때만, 주석 필수(린트 규칙 `unsafe_nonisolated_needs_comment`).
전역 가변 상태는 `@MainActor`, SDK 델리게이트는 `nonisolated`로 받고 `Task { @MainActor in }`으로 홉.

## 결과
- 앱 전체 컴파일 경고 0 상태로 Swift 6 모드.
- `nonisolated(unsafe)` 사용처 2곳(LiveActivity, Catalog), 모두 사유 주석.

## 재검토 조건
없음. 언어 기본값이 되었다.
