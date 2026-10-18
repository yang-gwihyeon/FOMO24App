# 원격 파이프라인 — 폰(Discord) → PR → TestFlight → 심사 준비

맥북은 집에, 요청은 폰에서. Claude Code 세션이 Discord DM으로 요청을 받아 아래 루프를 돌린다 (ADR-0010).

```
폰: "X 고쳐줘"
 └→ 브랜치 · 구현 · make ci · PR(6칸 카드) · CI 대기 ───────── Claude
     └→ 폰: "ㄱ"  → 머지 → make ship V=1.5 (CI → TestFlight) ── Claude
         └→ make smoke (4탭 순회 스크린샷) → Discord 보고 ─────── Claude  "너도 돌려봐"
         └→ asc.py wait-build → "1.5 (8) 테스트 가능" ─────────── Claude
             └→ 폰: TestFlight 설치·확인 ──────────────────────── 사람   "나도 돌려봐"
                 └→ asc.py prepare (버전·빌드·릴리즈 노트) · screenshots · metadata
                     └→ 폰: "제출 ㄱ" → asc.py submit ─────────── Claude  "심사 준비 완료"
```

## 명령 (전부 레포 안)
| 단계 | 명령 | 비고 |
|---|---|---|
| 상태 | `make status` | PR·CI·릴리즈·태그·ASC 빌드/버전 한 화면 |
| 검증 | `make ci` / `make smoke` | 유닛 + UI 스모크(`build/smoke/*.png`) |
| 빌드 업로드 | `make ship V=1.5` | 태그 없이 CI 수동 실행 → TestFlight. 반복 가능 |
| 최종 태그 | `make ship V=1.5 TAG=1` | `v1.5` 태그 푸시 (되돌리기 어려움) |
| 처리 대기 | `python3 scripts/asc/asc.py wait-build --version 1.5` | VALID = 폰에서 설치 가능 |
| 심사 준비 | `asc.py prepare --version 1.5 --notes-ko f --notes-en f` | 버전 생성·빌드 연결·What's New |
| 스크린샷 | `asc.py screenshots --version 1.5 --locale ko --device iphone67 --dir …` | 세트 교체 |
| 설명 등 | `asc.py metadata --version 1.5 --locale ko --field description --file …` | |
| 제출 | `asc.py submit --version 1.5` | **"제출 ㄱ" 후에만** |

## 확인 게이트 ("ㄱ" 규칙)
되돌리기 어려운 것은 Discord에서 명시 확인을 받은 뒤에만:
머지 · 태그 푸시 · 스크린샷/설명 교체 · **심사 제출**. 그 외(브랜치·PR·테스트 빌드·스모크)는 Claude가 진행하고 보고한다.

## 맥 쪽 준비
- `caffeinate -dims &` 또는 전원 설정에서 잠자기 방지. tmux 안에서 `claude` 실행, 재부팅 후 `claude --resume`.
- `.env`(루트, gitignored): ASC 키 — `scripts/asc/README.md`.
- `.claude/settings.local.json`에 `Bash(xcodebuild archive:*)`, `Bash(xcodebuild -exportArchive:*)` 허용 → CI가 죽었을 때 로컬 아카이브 폴백.
- 메모리 16 GB: 빌드 중 다른 무거운 앱 금지, `-jobs 4`.

## 실패 시 폴백
| 증상 | 대응 |
|---|---|
| 릴리즈 CI 업로드 실패 (서명 권한) | ASC 키 역할 확인 → 시크릿 교체. 그 동안 로컬 `xcodebuild archive` + `-exportArchive`(ExportOptions.plist) |
| 빌드 처리 FAILED/INVALID | `asc.py builds`로 상태, ASC 메일 확인 (대개 Info.plist·권한 문자열) |
| 스모크 실패 | `build/smoke/` 스크린샷과 xcresult로 원인 → 머지 보류 |
| 세션 끊김 | 맥에서 `claude --resume` — Discord 페어링은 유지됨 |

## 왜 이렇게 (요약, 상세는 ADR-0010)
- fastlane 대신 `xcodebuild` + ASC API 직접 호출: 의존성 0, 시크릿 3개, 스크립트 300줄. 스크린샷·메타데이터가 필요해져도(ADR-0004 재검토 조건) 같은 API로 충분했다.
- 테스트 빌드는 태그 없이: 태그는 "출시한 것"의 기록이어야 하므로.
- 사람 게이트는 4곳만: 자동화의 목적은 반복 작업 제거지 판단 제거가 아니다.
