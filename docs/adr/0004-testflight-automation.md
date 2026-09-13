# ADR-0004 태그 푸시 → TestFlight 자동 배포

## 맥락
수동 아카이브·업로드는 20분 이상 걸리고 빌드 번호 충돌(빌드 4 선점 사고)이 났다.

## 선택지
| | 장점 | 단점 |
|---|---|---|
| (a) Xcode 수동 | 설정 없음 | 시간·실수 |
| (b) fastlane match + gym | 성숙, 커뮤니티 | 인증서 저장소 관리, Ruby 의존 |
| (c) **xcodebuild + App Store Connect API 키 + 클라우드 서명** | 의존성 0, 시크릿 3개 | fastlane보다 기능 적음 |

## 결정
(c). `release.yml`: `v*` 태그 → 버전을 태그에서, 빌드 번호를 `github.run_number`에서 주입 → 아카이브 → 업로드.
빌드 번호를 CI가 소유하므로 충돌이 구조적으로 불가능.

## 결과
- 릴리즈 = `git tag v1.2 && git push origin v1.2`.
- 공개 저장소 → macOS 러너 무료. 비용 0.

## 재검토 조건
스크린샷 자동 업로드·메타데이터 관리가 필요해지면 fastlane deliver 부분 도입.
