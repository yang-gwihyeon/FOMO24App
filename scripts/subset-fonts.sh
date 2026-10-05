#!/usr/bin/env bash
# Pretendard 4종을 앱이 쓰는 글리프만 남겨 서브셋 → Resources/Fonts (ADR-0009).
# 원본은 scripts/fonts-src/ (수정 금지). 새 글자가 필요하면 font-unicodes.py를 고치고 다시 실행.
# 요구: fontTools (pip install fonttools) — pyftsubset
set -euo pipefail
cd "$(dirname "$0")/.."
PYFT="${PYFTSUBSET:-pyftsubset}"
UNICODES="$(python3 scripts/font-unicodes.py)"
for w in Regular Medium SemiBold Bold; do
  "$PYFT" "scripts/fonts-src/Pretendard-$w.otf" \
    --unicodes="$UNICODES" --layout-features='*' --name-IDs='*' --notdef-outline \
    --output-file="Resources/Fonts/Pretendard-$w.otf"
done
ls -la Resources/Fonts/*.otf | awk '{printf "%6.2f MB  %s\n", $5/1048576, $9}'
