# ADR-0001 Tuist로 프로젝트 정의를 코드화

## 맥락
`.xcodeproj`는 머지 충돌이 잦고 diff 리뷰가 불가능하다. 위젯·알림 익스텐션·테스트 타깃이 늘어나며 타깃 설정 중복이 커졌다.

## 선택지
| | 장점 | 단점 |
|---|---|---|
| (a) xcodeproj 직접 관리 | 도구 없음 | 충돌·리뷰 불가, 설정 중복 |
| (b) XcodeGen | 단순, YAML | 캐시·모듈 그래프 기능 없음 |
| (c) **Tuist** | Swift DSL, 타입 안전, 캐시·그래프, Environment 주입 | 설치 필요, 학습 비용 |

## 결정
(c) Tuist. `Project.swift` 단일 소스, 생성물은 gitignore. CI가 태그에서 버전을 `Environment`로 주입한다.

## 결과
- 타깃 6개(앱·위젯·알림 서비스·모듈 2·테스트 2)를 한 파일에서 관리.
- xcodeproj diff 0건. 설정 변경은 PR에서 Swift 코드로 리뷰.
- 비용: 새 기여자는 `make generate` 1회 필요. CI에 `brew install tuist` 약 1분.

## 재검토 조건
Xcode가 프로젝트 정의를 네이티브로 코드화하거나, 팀이 SwiftPM 단일 패키지 구조로 이전할 때.
