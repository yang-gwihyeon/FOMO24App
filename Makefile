# FOMO24 — 로컬과 CI가 같은 명령을 쓰기 위한 진입점.
# CI(.github/workflows/ci.yml)의 각 스텝은 여기 타깃과 1:1로 대응한다.
WORKSPACE   := FOMO24.xcworkspace
APP_SCHEME  := FOMO24
MOD_SCHEME  := Modules
PLIST       := GoogleService-Info.plist
BEAUTIFY    := $(shell command -v xcbeautify >/dev/null 2>&1 && echo "| xcbeautify" || echo "")
# 시뮬레이터는 이름 매칭이 모호할 수 있어 UDID로 고정 (CI와 동일 방식)
SIM_UDID    := $(shell xcrun simctl list devices available | grep iPhone | grep -m1 -oE '[0-9A-F-]{36}')

.PHONY: help generate test build lint lint-fix format format-check ci clean secrets perf-baseline

help: ## 타깃 목록
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

$(PLIST):
	@echo "→ 실제 $(PLIST) 없음: CI용 더미 복사 (커밋 금지)"
	@cp CI/GoogleService-Info.example.plist $(PLIST)

generate: $(PLIST) ## tuist generate (xcodeproj는 항상 재생성)
	tuist install 2>/dev/null || true
	tuist generate --no-open

test: generate ## 모듈 유닛테스트 (FOMOCore + MarketKit)
	set -o pipefail; xcodebuild test \
	  -workspace $(WORKSPACE) -scheme $(MOD_SCHEME) \
	  -destination "platform=iOS Simulator,id=$(SIM_UDID)" \
	  CODE_SIGNING_ALLOWED=NO $(BEAUTIFY)

build: generate ## 앱 + 익스텐션 시뮬레이터 빌드 (서명 없음)
	set -o pipefail; xcodebuild build \
	  -workspace $(WORKSPACE) -scheme $(APP_SCHEME) \
	  -destination 'generic/platform=iOS Simulator' \
	  CODE_SIGNING_ALLOWED=NO $(BEAUTIFY)

lint: ## SwiftLint (CODE_REVIEW.md 규칙)
	swiftlint lint --strict --quiet

lint-fix: ## SwiftLint 자동 수정 가능한 것만
	swiftlint lint --fix --quiet

format: ## SwiftFormat 적용
	swiftformat .

format-check: ## SwiftFormat 검사만 (CI용)
	swiftformat --lint .

secrets: ## 스테이징된 diff에서 키·토큰 패턴 검사
	@scripts/check-secrets.sh

ci: lint format-check test build ## CI와 동일 순서 전체 실행

perf-baseline: generate ## 성능 기준선 측정 안내 (docs/perf/README.md)
	@echo "docs/perf/README.md 의 B0 체크리스트를 따라 Instruments로 측정하고 결과를 docs/perf/ 에 기록하세요."
	@open -a Instruments || true

clean: ## 생성물 삭제
	rm -rf Derived FOMO24.xcodeproj FOMO24.xcworkspace build
	tuist clean 2>/dev/null || true
