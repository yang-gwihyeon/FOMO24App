# ADR-0009 Firestore SDK 제거 — REST API + 폰트 서브셋으로 앱 용량 최소화

## 맥락 (관찰)
ADR-0008(Phosphor 제거, -85 MB) 뒤에도 서명 없는 Release 기기 빌드가 **약 76 MB**였다. 분해 결과:

| 항목 | 크기 | 비고 |
|---|---|---|
| `grpc.framework` | 32.6 MB | Firestore 통신 스택 |
| `FirebaseFirestoreInternal.framework` | 11.4 MB | Firestore C++ 코어 |
| `openssl_grpc` + `absl` + `grpcpp` | 6.1 MB | Firestore 부속 |
| 앱 바이너리 | 19.3 MB | 앱 코드 + Firebase Core/Messaging/leveldb 정적 링크 |
| Pretendard 4종 | 6.0 MB | 한글 11,172자 전체 포함 |

앱이 Firestore로 하는 일은 `config/*` 문서 4개 읽기, `config/appUpdate` 감시, `alerts`·`laTokens` 문서 쓰기/삭제뿐이다.
전부 **문서 단건 get/set/delete**이며 쿼리·트랜잭션·오프라인 쓰기 큐를 쓰지 않는다. 이를 위해 gRPC 50 MB를 싣고 있었다.

## 선택지
| | 절감 | 단점 |
|---|---|---|
| (a) 유지 | 0 | 195 MB → 100 MB 안팎에서 멈춤 |
| **(b) Firestore SDK → REST API(URLSession), FCM(Messaging)은 유지** | **약 -50 MB** | 실시간 리스너 없음 → 강제 업데이트는 포그라운드 진입 시 폴링. SDK 오프라인 캐시 → 파일 캐시 직접 구현 |
| (c) Cloud Functions HTTPS 엔드포인트 | 약 -50 MB | 서버 코드·배포 필요, 앱과 서버 동시 변경 |
| (d) Firebase 전부 제거 (FCM → APNs 직접) | (b) + 약 -5 MB | 서버 푸시 경로 재작성 2~3일 |
| 폰트 (e) 전체 한글 유지 서브셋 | -0.3 MB/종 | 효과 없음 (측정: 1.50 → 1.23 MB) |
| **폰트 (f) KS X 1001 상용 2,350자 + 가나 + 소스 등장 문자** | **-4.4 MB** (6.0 → 1.6) | 희귀 한자음 글자는 시스템 폰트로 글리프 폴백 |

## 결정
(b) + (f). 판단 기준은 **서버 무변경**과 **한 코드 경로**(ADR-0007과 같은 기준).
- `Sources/Services/FirestoreREST.swift`: get/set(merge)/delete 3개만 구현. 인증은 SDK와 동일한 비로그인(API 키) — 접근 제어는 Firestore 보안 규칙이 담당하므로 권한 모델은 바뀌지 않는다.
- `Modules/FOMOCore/FirestoreJSON.swift`: REST 타입 태그(`{"integerValue":"5"}`) ↔ Swift 값 변환을 순수 함수로 두어 테스트한다. 서비스 파서(`init(remote:)`)는 SDK 시절 `[String: Any]`를 그대로 받는다.
- 서버 타임스탬프(`FieldValue.serverTimestamp()`)는 기기 시각으로 대체 — 서버는 `laTokens.startedAt`을 8.5시간 초과 판정에만 쓴다.
- `UpdateGate`: `addSnapshotListener` → 앱 시작·활성화 때 GET. 콘솔에서 플래그를 켜면 다음 포그라운드 진입 시 반영된다(실행 중 즉시 반영은 포기).
- 원격 설정 3종(카탈로그·시장시간·캘린더)은 마지막 성공 응답을 Caches에 저장해 오프라인 폴백.
- 폰트는 `scripts/subset-fonts.sh`(pyftsubset)로 재현. 원본은 `scripts/fonts-src/`, 필요한 글자 목록은 `scripts/font-unicodes.py`가 소스 코드를 스캔해 만든다 — UI 문자열에 새 희귀 글자가 들어가도 스크립트를 다시 돌리면 포함된다.

## 결과 (측정)
서명 없는 Release 기기 빌드(`xcodebuild -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`), 같은 Mac·같은 Xcode 26.4:

| | 전 (ADR-0008 후) | 후 |
|---|---|---|
| 앱 번들 합계 | 76 MB | **6.8 MB** |
| Firestore 동적 프레임워크 5종 | 50.1 MB | 0 |
| 앱 바이너리 | 19.3 MB | 4.4 MB |
| 폰트 4종 | 6.0 MB | 1.6 MB |

- FOMOCore 테스트 +8 (`FirestoreJSONTests`), 모듈 테스트 합계 50.
- 앱 바이너리 19.3 → 4.4 MB: Firestore Swift 래퍼·leveldb·nanopb·gRPC 글루 등 정적 링크분까지 함께 빠짐.
- REST 쓰기 검증: 보안 규칙(`fcmToken.size() > 20`, `laTokens.token.size() > 20`)을 만족하는 요청으로 create/merge/get/delete 전부 200 확인 (2026-09-28, 테스트 문서는 즉시 삭제).
- App Store 표시 용량: 194.9 MB(1.1) → (1.3 출시 후 기록).

## 재검토 조건
- Firestore 쿼리·실시간 구독·오프라인 쓰기 큐가 필요해지면 SDK 복귀 또는 (c) Cloud Functions.
- 강제 업데이트를 "실행 중 즉시" 반영해야 하면 FCM 데이터 메시지로 트리거.
- 폰트 폴백 글리프가 눈에 띄는 사용자 피드백이 오면 (f)의 글자 목록 확장.
