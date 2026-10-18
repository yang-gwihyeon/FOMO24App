#!/usr/bin/env bash
# "지금 어디까지 됐어?" — PR·CI·릴리즈·TestFlight·심사 상태 한 화면 요약.
# ASC 상태는 .env(ASC_KEY_ID 등)가 있을 때만 (scripts/asc/asc.py).
set -uo pipefail
cd "$(dirname "$0")/.."

echo "## 로컬"
echo "  브랜치: $(git branch --show-current) @ $(git rev-parse --short HEAD)  변경: $(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')개"
git fetch -q origin 2>/dev/null
ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null); behind=$(git rev-list --count HEAD..origin/main 2>/dev/null)
echo "  origin/main 대비: +${ahead:-?} / -${behind:-?}"

echo "## 열린 PR"
gh pr list --state open --json number,title,headRefName,statusCheckRollup --jq '
  if length==0 then "  (없음)" else .[] |
  "  #\(.number) \(.title) [\(.headRefName)] 체크: " +
  ([.statusCheckRollup[]? | select(.name|test("SwiftFormat|모듈 테스트")) | "\(.name|split(" ")[0])=\(.conclusion // .status)"] | join(", "))
  end'

echo "## main CI (최근 1건)"
gh run list --workflow=ci.yml --branch main --limit 1 --json conclusion,headSha,createdAt --jq '.[] | "  \(.conclusion) \(.headSha[:7]) \(.createdAt[:16])"'

echo "## 릴리즈 (TestFlight 업로드, 최근 3건)"
gh run list --workflow=release.yml --limit 3 --json number,conclusion,status,headBranch,createdAt,event --jq '.[] | "  run#\(.number) \(.headBranch) \(.event) \(.status)/\(.conclusion // "-") \(.createdAt[:16])"'

echo "## 태그"
echo "  $(git tag --sort=-creatordate | head -3 | tr '\n' ' ')"

if [[ -f .env ]]; then
  echo "## App Store Connect"
  python3 scripts/asc/asc.py status 2>&1 | sed 's/^/  /'
else
  echo "## App Store Connect: .env 없음 (scripts/asc/README 참고)"
fi
