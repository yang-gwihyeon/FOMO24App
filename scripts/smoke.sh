#!/usr/bin/env bash
# UI 스모크 테스트 실행 + 스크린샷 추출 → build/smoke/*.png
# 원격 파이프라인: Claude가 머지 전 실행해 결과 PNG를 Discord로 보고한다.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 16 Pro}"
UDID=$(xcrun simctl list devices available | grep "$SIM_NAME (" | grep -m1 -oE '[0-9A-F-]{36}')
[[ -n "$UDID" ]] || { echo "✗ 시뮬레이터 '$SIM_NAME' 없음"; exit 1; }
OUT=build/smoke
RESULT=build/smoke.xcresult
rm -rf "$OUT" "$RESULT"; mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

set +e
set -o pipefail
xcodebuild test \
  -workspace FOMO24.xcworkspace -scheme UISmoke \
  -destination "platform=iOS Simulator,id=$UDID" \
  -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | { command -v xcbeautify >/dev/null && xcbeautify || cat; }
status=$?
set -e

# Xcode 16+: 첨부 파일 일괄 추출
if xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT" >/dev/null 2>&1; then
  # 이름을 테스트에서 붙인 첨부 이름으로 정리 (manifest.json 참고)
  python3 - "$OUT" <<'EOF'
import json, os, sys, shutil
out = sys.argv[1]
m = os.path.join(out, "manifest.json")
if os.path.exists(m):
    for t in json.load(open(m)):
        for a in t.get("attachments", []):
            src = os.path.join(out, a["exportedFileName"])
            name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
            base = name.split("_")[0] if "_" in name else os.path.splitext(name)[0]
            dst = os.path.join(out, f"{base}.png")
            if os.path.exists(src) and src != dst:
                shutil.move(src, dst)
EOF
fi
echo "--- 스크린샷: $OUT"
ls -1 "$OUT"/*.png 2>/dev/null || echo "(없음)"
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
exit $status
