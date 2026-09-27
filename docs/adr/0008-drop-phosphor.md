# ADR-0008 Phosphor 아이콘 라이브러리 제거 — 사용하는 SVG 7개만 로컬 카탈로그로

## 맥락 (관찰)
App Store 표시 용량 **194.9 MB**. 기능(시세 목록·위젯·캘린더) 대비 과도. 기기용 Debug 빌드를 분해한 결과:

| 항목 | 크기 |
|---|---|
| `PhosphorSwift_PhosphorSwift.bundle/Assets.car` | **84.7 MB** |
| Pretendard 폰트 4종 | 6.0 MB |
| 앱 바이너리·Firebase | 나머지 |

PhosphorSwift 패키지는 아이콘 1,518종 × 6 웨이트 = **imageset 9,108개**를 하나의 Assets.car로 싣는다. 앱이 실제로 쓰는 아이콘은 `grep 'Ph\.'` 기준 **7개**(broadcast·bell-simple·bell-simple-ringing·arrow-right·plus·plus-circle·heartbeat).

## 선택지
| | 장점 | 단점 |
|---|---|---|
| (a) 유지 | 변경 없음 | 85MB가 7개 아이콘 값. 다운로드 이탈·셀룰러 200MB 제한 근접 |
| (b) SF Symbols로 교체 | 0 바이트, 의존성 0 | 아이콘 모양이 바뀜(디자인 정체성) |
| **(c) 쓰는 SVG 7개만 카탈로그에 복사, 패키지 제거** | 모양 유지, 64KB, 의존성 0 | 아이콘 추가 시 수동 복사 (MIT 라이선스 파일 동봉) |

## 결정
(c). 기준은 **모양 유지**와 **크기**. `PhIcon(.broadcastBold, color:)` 뷰 하나로 7개를 열거형으로 관리한다. 템플릿 렌더링이라 듀오톤 SVG의 20% 레이어 알파도 유지된다.
새 아이콘이 필요하면 phosphoricons.com 에서 SVG를 받아 `Resources/Assets.xcassets/PhosphorIcons/`에 추가하고 `PhIcon.Name`에 케이스를 더한다.

## 결과 (측정)
- Debug 기기 빌드(iPhone 15 Plus): **125 MB → 32 MB** (2026-09-27). 남은 32 MB 중 24 MB는 `FOMO24.debug.dylib`(Debug 전용, 출시 빌드 미포함) → 출시 번들 예상 약 8 MB + Firebase 프레임워크.
- App Store 표시 용량: 194.9 MB → (1.2 출시 후 기록)
- 변경 파일: `Project.swift`(패키지 제거), `PhIcon.swift`(신규), 뷰 3개, 카탈로그 SVG 7개 + 라이선스.

## 재검토 조건
아이콘이 30개를 넘어 수동 관리가 부담되면 SF Symbols 전환(b) 검토.
