# scripts/asc — App Store Connect API (심사 준비 자동화)

fastlane 없이 표준 라이브러리 + `cryptography`로 ASC API를 호출한다 (ADR-0010). Discord 원격 파이프라인의 마지막 단계.

## 설정 (1회)
1. App Store Connect > 사용자 및 액세스 > 통합 > App Store Connect API 에서 키 생성 (**App Manager** 이상).
2. `.p8`을 `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` 에 둔다 (xcodebuild/altool 기본 탐색 경로).
3. 레포 루트 `.env` (gitignored) — `scripts/asc/env.example` 복사:
   ```
   ASC_KEY_ID=…        # 키 ID
   ASC_ISSUER_ID=…     # 키 목록 페이지 상단 Issuer ID (UUID)
   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_….p8
   ASC_BUNDLE_ID=com.yang.FOMO24
   ```
4. `python3 scripts/asc/asc.py auth` → `✓ 인증 OK` 확인.

## 흐름
```
make ship V=1.5            # CI → TestFlight (태그 없이)   ← 테스트 빌드 반복
asc.py wait-build --version 1.5         # 처리 완료 = 폰에서 TestFlight 설치 가능
asc.py prepare --version 1.5 --notes-ko notes.ko.txt --notes-en notes.en.txt [--release manual]
asc.py screenshots --version 1.5 --locale ko --device iphone67 --dir AppStoreScreenshots/ko/iphone67
asc.py metadata --version 1.5 --locale ko --field description --file desc.ko.txt
asc.py status                            # 빌드·버전·심사 상태
make ship V=1.5 TAG=1      # 최종: v1.5 태그 (선택)
asc.py submit --version 1.5              # 심사 제출 — 사용자 "제출 ㄱ" 확인 후에만
```

## 규칙
- `submit`은 되돌리기 어렵다 → Discord에서 **"제출 ㄱ"** 를 받은 뒤에만 실행.
- 스크린샷·설명 변경은 먼저 Discord로 결과물을 보여주고 OK 받는다.
- 빌드 번호는 CI run number — 로컬에서 버전 기본값(`Project.swift`)을 올릴 필요 없음.
- 키 파일·`.env`는 절대 커밋하지 않는다 (`.gitignore` + `scripts/check-secrets.sh`).

## 스크린샷 디바이스 키
| `--device` | ASC displayType | 시뮬레이터 |
|---|---|---|
| iphone67 | APP_IPHONE_67 | iPhone 16 Pro Max (1320×2868) |
| iphone65 | APP_IPHONE_65 | iPhone 11 Pro Max (1242×2688) |
| ipad13 | APP_IPAD_PRO_3GEN_129 | iPad Pro 13" (2064×2752) |
