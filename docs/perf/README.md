# 성능 작업 기록 (docs/perf)

규칙: **측정 전에 고치지 않는다.** 항목당 파일 하나 `YYYY-MM-DD-<주제>.md`, 아래 카드 형식. Instruments 캡처는 `docs/perf/img/`.

## 카드 템플릿
```
# <주제>
## 관찰   도구 · 수치 · 재현 절차
## 가설
## 선택지 (최소 2개, 트레이드오프)
## 결정   판단 기준 명시
## 측정   전 → 후 (같은 절차·같은 기기·같은 빌드 구성)
## 배운 것
```

## B0 기준선 체크리스트 (모든 성능 작업의 전제)
측정 조건을 고정한다: 실기기(가능하면) · Release 구성 · 같은 종목 수 · Wi‑Fi · 저전력 모드 끔.

| # | 지표 | 도구 | 절차 | 기록 |
|---|---|---|---|---|
| 1 | 메모리 성장 | Instruments **Allocations** (+ Debug Navigator) | cold launch → 대시보드 30분 방치(5초 폴링 360회) → Persistent 바이트 그래프 기울기 | 시작/10/20/30분 MB |
| 2 | 누수 | Instruments **Leaks** + **Memory Graph** | 다이나믹 아일랜드 추적 시작→종료 10회 → Leaks 목록, `Task`/`LiveActivityManager` 인스턴스 수 | 누수 수, 인스턴스 수 |
| 3 | 렌더 부하 | Instruments **SwiftUI** (View Body 카운트) + **Time Profiler** | 대시보드 60초 스크롤 (정렬 = 수익률순) | body 호출 수, `sorted` 샘플 %, 평균 CPU % |
| 4 | 네트워크 | Instruments **Network** (또는 Proxyman) | 포그라운드 1분 | 요청 수/분, KB/분, 실패 수 |
| 5 | 배터리 | Instruments **Energy Log** | 포그라운드 30분 | 에너지 등급, 네트워크/CPU 비중 |
| 6 | 기동 | Xcode Organizer **Launch Time** / `os_signpost` | cold launch 10회 | 첫 프레임 ms, 첫 시세 표시 ms (평균·p90) |
| 7 | 위젯 메모리 | 위젯 익스텐션 프로세스 attach → Debug Navigator | 타임라인 갱신 5회 | 최대 MB (한도 30MB) |
| 8 | 빌드 시간 | `xcodebuild -showBuildTimingSummary`, CI 런 시간 | 클린 / 증분 각 3회 | 초, 모듈별 |

기준선 결과는 `2026-MM-DD-baseline.md` 한 파일에 표로. 이후 모든 카드의 "전" 수치는 이 파일을 인용한다.

## 가설 후보 (코드 리딩 기준, 2026-09-12) — 측정으로 확인 전까지는 가설
| ID | 위치 | 관찰 | 검증할 지표 |
|---|---|---|---|
| P1 | `PriceStore.displayedTickers` | computed property 안에서 매 접근 `sorted` | #3 body당 정렬 횟수 |
| P2 | `PriceStore.refresh()` | 5초마다 `quotes` 전체 교체 → `@Observable` 전체 변경 | #1 5초 주기 할당 스파이크, #3 행 리렌더 수 |
| P3 | `fetchAllSources()` | 5초 × 4거래소 = 분당 48요청, 매번 `makeService()` | #4, #5 |
| P4 | `LiveActivityManager.watchState` | 액티비티마다 무한 `for await` Task, `self` 강참조 | #2 반복 후 인스턴스 수 |
| P5 | `UpdateGate` Firestore 리스너 | 해제 경로 | #2, #4 |
| P6 | `PriceWidget` | 커스텀 폰트 로드 vs 30MB 한도 | #7 |
| P7 | 기동 | Firebase configure + 첫 폴링 직렬 | #6 |
| P8 | `DigestView:142` | 뷰 바디에서 포매터 생성 (린트 경고) | #3 |

## 면접 문장 (목표)
"고치기 전에 8개 지표의 기준선을 먼저 만들었고, 가설 8개 중 측정으로 확인된 것만 고쳤습니다. 확인되지 않은 것은 '문제 아님'으로 기록했습니다."
